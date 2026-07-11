#include <windows.h>

#include <portabledevice.h>
#include <portabledeviceapi.h>
#include <portabledevicetypes.h>
#include <propvarutil.h>
#include <wrl/client.h>

#include <algorithm>
#include <atomic>
#include <cerrno>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstdint>
#include <cwchar>
#include <cwctype>
#include <deque>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <limits>
#include <memory>
#include <mutex>
#include <optional>
#include <sstream>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

using Microsoft::WRL::ComPtr;

namespace {

constexpr unsigned int kSchemaVersion = 1;
constexpr unsigned int kDefaultObserveSeconds = 30;
constexpr unsigned int kDefaultMaxDepth = 8;
constexpr unsigned int kDefaultMaxObjects = 5'000;
constexpr unsigned int kMaximumObserveSeconds = 600;
constexpr unsigned int kMaximumPollSeconds = 60;
constexpr unsigned int kMaximumDepth = 16;
constexpr unsigned int kMaximumObjects = 50'000;
constexpr size_t kMaximumDisplayString = 512;
constexpr size_t kMaximumPathHint = 1'024;
constexpr size_t kMaximumQueuedEvents = 256;
constexpr size_t kMaximumEventRecords = 4'096;
constexpr size_t kMaximumObjectDetailRecords = 2'000;
constexpr size_t kMaximumEventDrivenRescans = 128;
constexpr size_t kMaximumEventIdentifierLength = 4'096;
constexpr size_t kMaximumWpdIdentifierLength = 4'096;
constexpr DWORD kMaximumDevices = 256;
constexpr DWORD kMaximumSupportedEvents = 256;
constexpr ULONG kEnumerationBatchSize = 32;

std::string Utf8(std::wstring_view value) {
    if (value.empty()) {
        return {};
    }

    const int required = WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0,
        nullptr,
        nullptr);
    if (required <= 0) {
        return "<invalid-unicode>";
    }

    std::string result(static_cast<size_t>(required), '\0');
    const int written = WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        value.data(),
        static_cast<int>(value.size()),
        result.data(),
        required,
        nullptr,
        nullptr);
    return written == required ? result : "<invalid-unicode>";
}

std::wstring Truncate(std::wstring value, size_t maximum) {
    if (value.size() <= maximum) {
        return value;
    }
    value.resize(maximum);
    value.append(L"\u2026");
    return value;
}

std::optional<std::wstring> CopyBoundedWideString(
    const wchar_t* value,
    size_t maximumLength) {
    if (value == nullptr) {
        return std::nullopt;
    }
    size_t length = 0;
    while (length <= maximumLength && value[length] != L'\0') {
        ++length;
    }
    if (length > maximumLength) {
        return std::nullopt;
    }
    return std::wstring(value, length);
}

std::string EscapeJson(std::string_view value) {
    std::ostringstream escaped;
    escaped << '"';
    for (const unsigned char character : value) {
        switch (character) {
        case '"':
            escaped << "\\\"";
            break;
        case '\\':
            escaped << "\\\\";
            break;
        case '\b':
            escaped << "\\b";
            break;
        case '\f':
            escaped << "\\f";
            break;
        case '\n':
            escaped << "\\n";
            break;
        case '\r':
            escaped << "\\r";
            break;
        case '\t':
            escaped << "\\t";
            break;
        default:
            if (character < 0x20) {
                escaped << "\\u00" << std::hex << std::setw(2) << std::setfill('0')
                        << static_cast<unsigned int>(character) << std::dec;
            } else {
                escaped << character;
            }
            break;
        }
    }
    escaped << '"';
    return escaped.str();
}

std::string UtcTimestamp() {
    SYSTEMTIME time{};
    GetSystemTime(&time);
    char buffer[32]{};
    std::snprintf(
        buffer,
        sizeof(buffer),
        "%04u-%02u-%02uT%02u:%02u:%02u.%03uZ",
        static_cast<unsigned int>(time.wYear),
        static_cast<unsigned int>(time.wMonth),
        static_cast<unsigned int>(time.wDay),
        static_cast<unsigned int>(time.wHour),
        static_cast<unsigned int>(time.wMinute),
        static_cast<unsigned int>(time.wSecond),
        static_cast<unsigned int>(time.wMilliseconds));
    return buffer;
}

std::string HResultString(HRESULT result) {
    std::ostringstream output;
    output << "0x" << std::hex << std::uppercase << std::setw(8) << std::setfill('0')
           << static_cast<uint32_t>(result);
    return output.str();
}

std::string GuidString(REFGUID value) {
    wchar_t buffer[64]{};
    const int count = StringFromGUID2(value, buffer, static_cast<int>(std::size(buffer)));
    if (count <= 1) {
        return "<invalid-guid>";
    }
    return Utf8(std::wstring_view(buffer, static_cast<size_t>(count - 1)));
}

class JsonLine {
public:
    JsonLine& String(std::string key, std::string value) {
        fields_.emplace_back(std::move(key), EscapeJson(value));
        return *this;
    }

    JsonLine& WideString(std::string key, std::wstring_view value) {
        return String(std::move(key), Utf8(value));
    }

    JsonLine& Number(std::string key, uint64_t value) {
        fields_.emplace_back(std::move(key), std::to_string(value));
        return *this;
    }

    JsonLine& Boolean(std::string key, bool value) {
        fields_.emplace_back(std::move(key), value ? "true" : "false");
        return *this;
    }

    JsonLine& Null(std::string key) {
        fields_.emplace_back(std::move(key), "null");
        return *this;
    }

    [[nodiscard]] std::string Render() const {
        std::ostringstream output;
        output << '{';
        for (size_t index = 0; index < fields_.size(); ++index) {
            if (index != 0) {
                output << ',';
            }
            output << EscapeJson(fields_[index].first) << ':' << fields_[index].second;
        }
        output << '}';
        return output.str();
    }

private:
    std::vector<std::pair<std::string, std::string>> fields_;
};

JsonLine EventLine(std::string name) {
    JsonLine line;
    line.String("event", std::move(name)).String("timestamp", UtcTimestamp());
    return line;
}

class JsonEmitter {
public:
    void Emit(const JsonLine& line) {
        std::scoped_lock lock(mutex_);
        std::cout << line.Render() << '\n';
        std::cout.flush();
    }

private:
    std::mutex mutex_;
};

struct Options {
    unsigned int observeSeconds = kDefaultObserveSeconds;
    unsigned int pollSeconds = 0;
    unsigned int maxDepth = kDefaultMaxDepth;
    unsigned int maxObjects = kDefaultMaxObjects;
    bool includeAllDevices = false;
    bool showMetadata = false;
    bool showIds = false;
    bool help = false;
    std::optional<size_t> deviceIndex;
};

bool ParseUnsigned(
    const wchar_t* text,
    unsigned int minimum,
    unsigned int maximum,
    unsigned int& output) {
    if (text == nullptr || *text == L'\0' || *text == L'-') {
        return false;
    }

    wchar_t* end = nullptr;
    errno = 0;
    const unsigned long parsed = std::wcstoul(text, &end, 10);
    if (errno != 0 || end == text || *end != L'\0' || parsed < minimum || parsed > maximum) {
        return false;
    }
    output = static_cast<unsigned int>(parsed);
    return true;
}

bool ParseOptions(int argc, wchar_t** argv, Options& options, std::wstring& error) {
    for (int index = 1; index < argc; ++index) {
        const std::wstring_view argument(argv[index]);
        if (argument == L"--help" || argument == L"-h") {
            options.help = true;
        } else if (argument == L"--all-devices") {
            options.includeAllDevices = true;
        } else if (argument == L"--show-metadata") {
            options.showMetadata = true;
        } else if (argument == L"--show-ids") {
            options.showIds = true;
        } else if (argument == L"--observe-seconds" || argument == L"--poll-interval" ||
                   argument == L"--max-depth" || argument == L"--max-objects" ||
                   argument == L"--device-index") {
            if (index + 1 >= argc) {
                error = L"missing value after " + std::wstring(argument);
                return false;
            }

            unsigned int value = 0;
            if (argument == L"--observe-seconds") {
                if (!ParseUnsigned(argv[++index], 0, kMaximumObserveSeconds, value)) {
                    error = L"--observe-seconds must be between 0 and 600";
                    return false;
                }
                options.observeSeconds = value;
            } else if (argument == L"--poll-interval") {
                if (!ParseUnsigned(argv[++index], 0, kMaximumPollSeconds, value)) {
                    error = L"--poll-interval must be between 0 and 60";
                    return false;
                }
                options.pollSeconds = value;
            } else if (argument == L"--max-depth") {
                if (!ParseUnsigned(argv[++index], 1, kMaximumDepth, value)) {
                    error = L"--max-depth must be between 1 and 16";
                    return false;
                }
                options.maxDepth = value;
            } else if (argument == L"--max-objects") {
                if (!ParseUnsigned(argv[++index], 1, kMaximumObjects, value)) {
                    error = L"--max-objects must be between 1 and 50000";
                    return false;
                }
                options.maxObjects = value;
            } else {
                if (!ParseUnsigned(argv[++index], 0, kMaximumObjects, value)) {
                    error = L"--device-index must be a non-negative integer";
                    return false;
                }
                options.deviceIndex = static_cast<size_t>(value);
            }
        } else {
            error = L"unknown argument: " + std::wstring(argument);
            return false;
        }
    }
    return true;
}

void PrintUsage() {
    std::cout
        << "PhoneSnap WPD capability probe (read-only)\n\n"
        << "Usage: WpdProbe.exe [options]\n\n"
        << "  --observe-seconds N  Event observation window, 0-600 (default 30)\n"
        << "  --poll-interval N    Re-enumeration interval, 0-60; 0 disables timer polling\n"
        << "  --max-depth N        Maximum content-tree depth, 1-16 (default 8)\n"
        << "  --max-objects N      Maximum objects per catalog, 1-50000 (default 5000)\n"
        << "  --device-index N     Probe only zero-based WPD enumeration index N\n"
        << "  --all-devices        Probe non-Apple WPD devices too\n"
        << "  --show-metadata      Include names, paths, dates, sizes, and dimensions\n"
        << "  --show-ids           Include raw PnP, object, and persistent IDs (sensitive)\n"
        << "  --help               Show this help\n";
}

class ComApartment {
public:
    ComApartment() : result_(CoInitializeEx(nullptr, COINIT_MULTITHREADED)) {}

    ~ComApartment() {
        if (SUCCEEDED(result_)) {
            CoUninitialize();
        }
    }

    [[nodiscard]] HRESULT Result() const { return result_; }

private:
    HRESULT result_;
};

std::wstring Lowercase(std::wstring_view value) {
    std::wstring lowered(value);
    std::transform(lowered.begin(), lowered.end(), lowered.begin(), [](wchar_t character) {
        return static_cast<wchar_t>(std::towlower(character));
    });
    return lowered;
}

bool ContainsInsensitive(std::wstring_view haystack, std::wstring_view needle) {
    return Lowercase(haystack).find(Lowercase(needle)) != std::wstring::npos;
}

template <typename Getter>
std::wstring QueryManagerString(Getter&& getter) {
    DWORD characterCount = 0;
    HRESULT result = getter(nullptr, &characterCount);
    if (FAILED(result) || characterCount == 0 || characterCount > 32'768) {
        return {};
    }

    std::vector<wchar_t> buffer(characterCount, L'\0');
    result = getter(buffer.data(), &characterCount);
    if (FAILED(result) || buffer.empty()) {
        return {};
    }
    return Truncate(std::wstring(buffer.data()), kMaximumDisplayString);
}

struct DeviceInfo {
    size_t index = 0;
    std::wstring pnpId;
    std::wstring friendlyName;
    std::wstring manufacturer;
    std::wstring description;
    bool appleCandidate = false;

    [[nodiscard]] std::string Reference() const {
        return "device-" + std::to_string(index + 1);
    }
};

bool IsAppleCandidate(const DeviceInfo& device) {
    return ContainsInsensitive(device.manufacturer, L"apple") ||
           ContainsInsensitive(device.friendlyName, L"iphone") ||
           ContainsInsensitive(device.friendlyName, L"ipad") ||
           ContainsInsensitive(device.friendlyName, L"ipod") ||
           ContainsInsensitive(device.description, L"iphone") ||
           ContainsInsensitive(device.description, L"ipad") ||
           ContainsInsensitive(device.description, L"ipod") ||
           ContainsInsensitive(device.description, L"apple") ||
           ContainsInsensitive(device.pnpId, L"vid_05ac");
}

HRESULT EnumerateDevices(IPortableDeviceManager* manager, std::vector<DeviceInfo>& devices) {
    DWORD count = 0;
    HRESULT result = manager->GetDevices(nullptr, &count);
    if (result != S_OK || count == 0) {
        return result;
    }
    if (count > kMaximumDevices) {
        return HRESULT_FROM_WIN32(ERROR_BUFFER_OVERFLOW);
    }

    std::vector<PWSTR> ids(count, nullptr);
    result = manager->GetDevices(ids.data(), &count);
    if (result != S_OK) {
        for (PWSTR id : ids) {
            CoTaskMemFree(id);
        }
        return result;
    }

    devices.reserve(count);
    for (DWORD index = 0; index < count; ++index) {
        if (ids[index] == nullptr) {
            continue;
        }

        DeviceInfo device;
        device.index = index;
        const std::optional<std::wstring> boundedPnpId =
            CopyBoundedWideString(ids[index], kMaximumWpdIdentifierLength);
        if (!boundedPnpId.has_value()) {
            continue;
        }
        device.pnpId = *boundedPnpId;
        device.friendlyName = QueryManagerString([&](PWSTR buffer, DWORD* size) {
            return manager->GetDeviceFriendlyName(ids[index], buffer, size);
        });
        device.manufacturer = QueryManagerString([&](PWSTR buffer, DWORD* size) {
            return manager->GetDeviceManufacturer(ids[index], buffer, size);
        });
        device.description = QueryManagerString([&](PWSTR buffer, DWORD* size) {
            return manager->GetDeviceDescription(ids[index], buffer, size);
        });
        device.appleCandidate = IsAppleCandidate(device);
        devices.push_back(std::move(device));
    }

    for (PWSTR id : ids) {
        CoTaskMemFree(id);
    }
    return S_OK;
}

HRESULT OpenReadOnly(const DeviceInfo& info, ComPtr<IPortableDevice>& device) {
    ComPtr<IPortableDeviceValues> clientInformation;
    HRESULT result = CoCreateInstance(
        CLSID_PortableDeviceValues,
        nullptr,
        CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&clientInformation));
    if (result != S_OK || clientInformation.Get() == nullptr) {
        return result == S_OK ? E_UNEXPECTED : result;
    }

    // WPD defaults to GENERIC_READ | GENERIC_WRITE. This probe deliberately
    // overrides that default before opening any device.
    result = clientInformation->SetUnsignedIntegerValue(WPD_CLIENT_DESIRED_ACCESS, GENERIC_READ);
    if (result != S_OK) {
        return result;
    }
    result = clientInformation->SetStringValue(WPD_CLIENT_NAME, L"PhoneSnap WPD Probe");
    if (result != S_OK) {
        return result;
    }
    result = clientInformation->SetUnsignedIntegerValue(WPD_CLIENT_MAJOR_VERSION, 1);
    if (result != S_OK) {
        return result;
    }
    result = clientInformation->SetUnsignedIntegerValue(WPD_CLIENT_MINOR_VERSION, 0);
    if (result != S_OK) {
        return result;
    }
    result = clientInformation->SetUnsignedIntegerValue(WPD_CLIENT_REVISION, 0);
    if (result != S_OK) {
        return result;
    }
    result = clientInformation->SetUnsignedIntegerValue(
        WPD_CLIENT_SECURITY_QUALITY_OF_SERVICE,
        SECURITY_IMPERSONATION);
    if (result != S_OK) {
        return result;
    }

    result = CoCreateInstance(
        CLSID_PortableDeviceFTM,
        nullptr,
        CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&device));
    if (result != S_OK || device.Get() == nullptr) {
        return result == S_OK ? E_UNEXPECTED : result;
    }
    return device->Open(info.pnpId.c_str(), clientInformation.Get());
}

std::string KnownEventName(REFGUID eventId) {
    if (IsEqualGUID(eventId, WPD_EVENT_OBJECT_ADDED)) {
        return "OBJECT_ADDED";
    }
    if (IsEqualGUID(eventId, WPD_EVENT_OBJECT_REMOVED)) {
        return "OBJECT_REMOVED";
    }
    if (IsEqualGUID(eventId, WPD_EVENT_OBJECT_UPDATED)) {
        return "OBJECT_UPDATED";
    }
    if (IsEqualGUID(eventId, WPD_EVENT_DEVICE_REMOVED)) {
        return "DEVICE_REMOVED";
    }
    if (IsEqualGUID(eventId, WPD_EVENT_DEVICE_RESET)) {
        return "DEVICE_RESET";
    }
    if (IsEqualGUID(eventId, WPD_EVENT_DEVICE_CAPABILITIES_UPDATED)) {
        return "DEVICE_CAPABILITIES_UPDATED";
    }
    if (IsEqualGUID(eventId, WPD_EVENT_STORAGE_FORMAT)) {
        return "STORAGE_FORMAT";
    }
    if (IsEqualGUID(eventId, WPD_EVENT_OBJECT_TRANSFER_REQUESTED)) {
        return "OBJECT_TRANSFER_REQUESTED";
    }
    return "UNKNOWN";
}

struct SupportedEventSummary {
    bool querySucceeded = false;
    bool objectAddedAdvertised = false;
    bool objectAddedBroadcast = false;
    uint64_t count = 0;
};

SupportedEventSummary ReportSupportedEvents(
    IPortableDevice* device,
    const DeviceInfo& info,
    const std::shared_ptr<JsonEmitter>& emitter) {
    SupportedEventSummary summary;
    ComPtr<IPortableDeviceCapabilities> capabilities;
    HRESULT result = device->Capabilities(&capabilities);
    if (result != S_OK || capabilities.Get() == nullptr) {
        const HRESULT effectiveResult = result == S_OK ? E_UNEXPECTED : result;
        auto line = EventLine("capability_error");
        line.String("device_ref", info.Reference())
            .String("stage", "Capabilities")
            .String("hresult", HResultString(effectiveResult));
        emitter->Emit(line);
        return summary;
    }

    ComPtr<IPortableDevicePropVariantCollection> events;
    result = capabilities->GetSupportedEvents(&events);
    if (result != S_OK || events.Get() == nullptr) {
        const HRESULT effectiveResult = result == S_OK ? E_UNEXPECTED : result;
        auto line = EventLine("capability_error");
        line.String("device_ref", info.Reference())
            .String("stage", "GetSupportedEvents")
            .String("hresult", HResultString(effectiveResult));
        emitter->Emit(line);
        return summary;
    }

    DWORD count = 0;
    result = events->GetCount(&count);
    if (result != S_OK) {
        auto line = EventLine("capability_error");
        line.String("device_ref", info.Reference())
            .String("stage", "GetSupportedEvents.GetCount")
            .String("hresult", HResultString(result));
        emitter->Emit(line);
        return summary;
    }
    summary.querySucceeded = true;
    summary.count = count;

    const DWORD eventsToReport = std::min(count, kMaximumSupportedEvents);
    for (DWORD index = 0; index < eventsToReport; ++index) {
        PROPVARIANT value;
        PropVariantInit(&value);
        result = events->GetAt(index, &value);
        if (result != S_OK || value.vt != VT_CLSID || value.puuid == nullptr) {
            auto line = EventLine("capability_event_error");
            line.String("device_ref", info.Reference())
                .Number("event_index", index)
                .String("hresult", HResultString(result))
                .Number("variant_type", value.vt);
            emitter->Emit(line);
            PropVariantClear(&value);
            continue;
        }

        const GUID eventId = *value.puuid;
        const bool isObjectAdded = IsEqualGUID(eventId, WPD_EVENT_OBJECT_ADDED);
        BOOL isBroadcast = FALSE;
        ComPtr<IPortableDeviceValues> eventOptions;
        const HRESULT optionsResult = capabilities->GetEventOptions(eventId, &eventOptions);
        const HRESULT effectiveOptionsResult =
            optionsResult == S_OK && eventOptions.Get() == nullptr
            ? E_UNEXPECTED
            : optionsResult;
        HRESULT broadcastResult = E_NOINTERFACE;
        if (effectiveOptionsResult == S_OK) {
            broadcastResult = eventOptions->GetBoolValue(
                WPD_EVENT_OPTION_IS_BROADCAST_EVENT,
                &isBroadcast);
        }

        if (isObjectAdded) {
            summary.objectAddedAdvertised = true;
            summary.objectAddedBroadcast = broadcastResult == S_OK && isBroadcast == TRUE;
        }

        auto line = EventLine("supported_event");
        line.String("device_ref", info.Reference())
            .Number("event_index", index)
            .String("event_name", KnownEventName(eventId))
            .String("event_id", GuidString(eventId))
            .Boolean("is_object_added", isObjectAdded)
            .Boolean("is_broadcast", broadcastResult == S_OK && isBroadcast == TRUE)
            .Boolean("event_options_query_succeeded", effectiveOptionsResult == S_OK)
            .Boolean("broadcast_value_query_succeeded", broadcastResult == S_OK)
            .String("broadcast_value_hresult", HResultString(broadcastResult));
        if (effectiveOptionsResult != S_OK) {
            line.String("event_options_hresult", HResultString(effectiveOptionsResult));
        }
        emitter->Emit(line);
        PropVariantClear(&value);
    }

    auto line = EventLine("supported_events_summary");
    line.String("device_ref", info.Reference())
        .Number("supported_event_count", summary.count)
        .Number("supported_events_reported", eventsToReport)
        .Boolean("supported_event_list_truncated", count > eventsToReport)
        .Boolean("object_added_advertised", summary.objectAddedAdvertised)
        .Boolean("object_added_broadcast", summary.objectAddedBroadcast);
    emitter->Emit(line);
    return summary;
}

class ObjectReferences {
public:
    explicit ObjectReferences(size_t maximumReferences)
        : maximumReferences_(maximumReferences) {}

    std::optional<uint64_t> Reference(const std::wstring& objectId) {
        if (objectId.empty()) {
            return std::nullopt;
        }
        std::scoped_lock lock(mutex_);
        const auto found = references_.find(objectId);
        if (found != references_.end()) {
            return found->second;
        }
        if (references_.size() >= maximumReferences_) {
            limitReached_ = true;
            return std::nullopt;
        }
        const uint64_t reference = next_++;
        references_.emplace(objectId, reference);
        return reference;
    }

    [[nodiscard]] bool LimitReached() const {
        std::scoped_lock lock(mutex_);
        return limitReached_;
    }

private:
    mutable std::mutex mutex_;
    std::unordered_map<std::wstring, uint64_t> references_;
    size_t maximumReferences_;
    uint64_t next_ = 1;
    bool limitReached_ = false;
};

struct QueuedWpdEvent {
    GUID eventId{};
    HRESULT eventIdResult = E_FAIL;
    std::wstring objectId;
    std::wstring parentId;
    std::wstring parentPersistentId;
    BOOL hierarchyChanged = FALSE;
    HRESULT hierarchyChangedResult = E_FAIL;
    bool identifierTruncated = false;
};

struct EventDrain {
    std::vector<QueuedWpdEvent> records;
    size_t droppedRecords = 0;
};

class BoundedEventQueue {
public:
    void Push(QueuedWpdEvent record) {
        {
            std::scoped_lock lock(mutex_);
            if (records_.size() >= kMaximumQueuedEvents) {
                ++droppedSinceDrain_;
            } else {
                records_.push_back(std::move(record));
            }
        }
        condition_.notify_one();
    }

    EventDrain DrainUntil(std::chrono::steady_clock::time_point deadline) {
        std::unique_lock lock(mutex_);
        condition_.wait_until(lock, deadline, [&] {
            return !records_.empty() || droppedSinceDrain_ != 0;
        });

        EventDrain drain;
        drain.records.reserve(records_.size());
        while (!records_.empty()) {
            drain.records.push_back(std::move(records_.front()));
            records_.pop_front();
        }
        drain.droppedRecords = std::exchange(droppedSinceDrain_, 0);
        return drain;
    }

private:
    std::mutex mutex_;
    std::condition_variable condition_;
    std::deque<QueuedWpdEvent> records_;
    size_t droppedSinceDrain_ = 0;
};

std::optional<std::wstring> GetOptionalString(
    IPortableDeviceValues* values,
    REFPROPERTYKEY key) {
    PWSTR allocated = nullptr;
    const HRESULT result = values->GetStringValue(key, &allocated);
    if (FAILED(result) || allocated == nullptr) {
        CoTaskMemFree(allocated);
        return std::nullopt;
    }
    const std::optional<std::wstring> value =
        CopyBoundedWideString(allocated, kMaximumWpdIdentifierLength);
    CoTaskMemFree(allocated);
    return value;
}

std::optional<GUID> GetOptionalGuid(IPortableDeviceValues* values, REFPROPERTYKEY key) {
    GUID value{};
    if (FAILED(values->GetGuidValue(key, &value))) {
        return std::nullopt;
    }
    return value;
}

std::optional<uint64_t> GetOptionalUnsignedLarge(
    IPortableDeviceValues* values,
    REFPROPERTYKEY key) {
    ULONGLONG value = 0;
    if (FAILED(values->GetUnsignedLargeIntegerValue(key, &value))) {
        return std::nullopt;
    }
    return static_cast<uint64_t>(value);
}

std::optional<uint64_t> GetOptionalUnsigned(
    IPortableDeviceValues* values,
    REFPROPERTYKEY key) {
    ULONG value = 0;
    if (FAILED(values->GetUnsignedIntegerValue(key, &value))) {
        return std::nullopt;
    }
    return static_cast<uint64_t>(value);
}

std::optional<std::string> GetOptionalDate(
    IPortableDeviceValues* values,
    REFPROPERTYKEY key) {
    PROPVARIANT value;
    PropVariantInit(&value);
    const HRESULT result = values->GetValue(key, &value);
    if (FAILED(result)) {
        PropVariantClear(&value);
        return std::nullopt;
    }

    SYSTEMTIME time{};
    bool converted = false;
    if (value.vt == VT_DATE) {
        converted = VariantTimeToSystemTime(value.date, &time) == TRUE;
    } else if (value.vt == VT_FILETIME) {
        converted = FileTimeToSystemTime(&value.filetime, &time) == TRUE;
    }
    PropVariantClear(&value);
    if (!converted) {
        return std::nullopt;
    }

    char buffer[32]{};
    std::snprintf(
        buffer,
        sizeof(buffer),
        "%04u-%02u-%02uT%02u:%02u:%02u.%03u",
        static_cast<unsigned int>(time.wYear),
        static_cast<unsigned int>(time.wMonth),
        static_cast<unsigned int>(time.wDay),
        static_cast<unsigned int>(time.wHour),
        static_cast<unsigned int>(time.wMinute),
        static_cast<unsigned int>(time.wSecond),
        static_cast<unsigned int>(time.wMilliseconds));
    return buffer;
}

std::string ContentTypeName(const std::optional<GUID>& value) {
    if (!value.has_value()) {
        return "UNAVAILABLE";
    }
    if (IsEqualGUID(*value, WPD_CONTENT_TYPE_IMAGE)) {
        return "IMAGE";
    }
    if (IsEqualGUID(*value, WPD_CONTENT_TYPE_FOLDER)) {
        return "FOLDER";
    }
    if (IsEqualGUID(*value, WPD_CONTENT_TYPE_FUNCTIONAL_OBJECT)) {
        return "FUNCTIONAL_OBJECT";
    }
    return "OTHER";
}

std::string FormatName(const std::optional<GUID>& value) {
    if (!value.has_value()) {
        return "UNAVAILABLE";
    }
    if (IsEqualGUID(*value, WPD_OBJECT_FORMAT_PNG)) {
        return "PNG";
    }
    if (IsEqualGUID(*value, WPD_OBJECT_FORMAT_EXIF)) {
        return "EXIF";
    }
    if (IsEqualGUID(*value, WPD_OBJECT_FORMAT_JFIF)) {
        return "JFIF";
    }
    if (IsEqualGUID(*value, WPD_OBJECT_FORMAT_TIFF)) {
        return "TIFF";
    }
    if (IsEqualGUID(*value, WPD_OBJECT_FORMAT_GIF)) {
        return "GIF";
    }
    if (IsEqualGUID(*value, WPD_OBJECT_FORMAT_BMP)) {
        return "BMP";
    }
    return "OTHER";
}

bool HasImageExtension(std::wstring_view name) {
    const std::wstring lowered = Lowercase(name);
    constexpr std::wstring_view extensions[] = {
        L".png", L".jpg", L".jpeg", L".heic", L".heif", L".tif", L".tiff", L".gif", L".bmp"};
    for (const std::wstring_view extension : extensions) {
        if (lowered.size() >= extension.size() &&
            lowered.compare(lowered.size() - extension.size(), extension.size(), extension) == 0) {
            return true;
        }
    }
    return false;
}

struct CatalogEntry {
    std::wstring objectId;
    std::wstring persistentId;
    std::wstring parentId;
    std::wstring name;
    std::wstring originalFilename;
    std::wstring pathHint;
    std::optional<GUID> contentType;
    std::optional<GUID> format;
    std::optional<uint64_t> size;
    std::optional<uint64_t> width;
    std::optional<uint64_t> height;
    std::optional<std::string> dateCreated;
    unsigned int depth = 0;
    bool isImage = false;
    bool isDcimLike = false;

    [[nodiscard]] std::wstring Identity() const {
        return persistentId.empty() ? L"object:" + objectId : L"persistent:" + persistentId;
    }

    [[nodiscard]] bool IsInteresting() const {
        return isImage || isDcimLike;
    }
};

struct CatalogResult {
    std::vector<CatalogEntry> entries;
    uint64_t objectsVisited = 0;
    uint64_t propertyFailures = 0;
    uint64_t propertySFalseResults = 0;
    bool depthLimitReached = false;
    bool objectLimitReached = false;
    std::optional<HRESULT> fatalHresult;
    std::string fatalStage;
};

HRESULT CreatePropertyKeyCollection(ComPtr<IPortableDeviceKeyCollection>& keys) {
    HRESULT result = CoCreateInstance(
        CLSID_PortableDeviceKeyCollection,
        nullptr,
        CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&keys));
    if (FAILED(result)) {
        return result;
    }

    const PROPERTYKEY requestedKeys[] = {
        WPD_OBJECT_NAME,
        WPD_OBJECT_ORIGINAL_FILE_NAME,
        WPD_OBJECT_PARENT_ID,
        WPD_OBJECT_PERSISTENT_UNIQUE_ID,
        WPD_OBJECT_CONTENT_TYPE,
        WPD_OBJECT_FORMAT,
        WPD_OBJECT_SIZE,
        WPD_OBJECT_DATE_CREATED,
        WPD_MEDIA_WIDTH,
        WPD_MEDIA_HEIGHT,
    };
    for (const PROPERTYKEY& key : requestedKeys) {
        result = keys->Add(key);
        if (FAILED(result)) {
            return result;
        }
    }
    return S_OK;
}

std::wstring JoinPathHint(std::wstring_view parent, std::wstring_view name) {
    std::wstring result;
    result.reserve(std::min(kMaximumPathHint, parent.size() + name.size() + 1));
    if (!parent.empty()) {
        result.append(parent);
        result.push_back(L'/');
    }
    result.append(name.empty() ? L"<unnamed>" : name);
    return Truncate(std::move(result), kMaximumPathHint);
}

CatalogResult BuildCatalog(
    IPortableDevice* device,
    unsigned int maxDepth,
    unsigned int maxObjects) {
    CatalogResult catalog;

    ComPtr<IPortableDeviceContent> content;
    HRESULT result = device->Content(&content);
    if (result != S_OK || content.Get() == nullptr) {
        catalog.fatalHresult = result == S_OK ? E_UNEXPECTED : result;
        catalog.fatalStage = "Content";
        return catalog;
    }

    ComPtr<IPortableDeviceProperties> properties;
    result = content->Properties(&properties);
    if (result != S_OK || properties.Get() == nullptr) {
        catalog.fatalHresult = result == S_OK ? E_UNEXPECTED : result;
        catalog.fatalStage = "Properties";
        return catalog;
    }

    ComPtr<IPortableDeviceKeyCollection> keys;
    result = CreatePropertyKeyCollection(keys);
    if (result != S_OK || keys.Get() == nullptr) {
        catalog.fatalHresult = result == S_OK ? E_UNEXPECTED : result;
        catalog.fatalStage = "CreatePropertyKeyCollection";
        return catalog;
    }

    struct PendingParent {
        std::wstring objectId;
        std::wstring pathHint;
        unsigned int childDepth = 1;
    };
    std::deque<PendingParent> pending;
    pending.push_back({WPD_DEVICE_OBJECT_ID, L"", 1});

    while (!pending.empty() && catalog.objectsVisited < maxObjects) {
        PendingParent parent = std::move(pending.front());
        pending.pop_front();
        if (parent.childDepth > maxDepth) {
            catalog.depthLimitReached = true;
            continue;
        }

        ComPtr<IEnumPortableDeviceObjectIDs> enumerator;
        result = content->EnumObjects(0, parent.objectId.c_str(), nullptr, &enumerator);
        if (result != S_OK || enumerator.Get() == nullptr) {
            if (parent.objectId == WPD_DEVICE_OBJECT_ID) {
                catalog.fatalHresult = result == S_OK ? E_UNEXPECTED : result;
                catalog.fatalStage = "EnumObjectsRoot";
                return catalog;
            }
            ++catalog.propertyFailures;
            continue;
        }

        bool folderHasMore = true;
        while (folderHasMore && catalog.objectsVisited < maxObjects) {
            PWSTR ids[kEnumerationBatchSize]{};
            ULONG fetched = 0;
            result = enumerator->Next(kEnumerationBatchSize, ids, &fetched);
            if (FAILED(result)) {
                ++catalog.propertyFailures;
                for (PWSTR id : ids) {
                    CoTaskMemFree(id);
                }
                break;
            }
            folderHasMore = result == S_OK && fetched != 0;

            for (ULONG index = 0; index < fetched; ++index) {
                if (catalog.objectsVisited >= maxObjects) {
                    catalog.objectLimitReached = true;
                    CoTaskMemFree(ids[index]);
                    ids[index] = nullptr;
                    continue;
                }
                if (ids[index] == nullptr) {
                    continue;
                }

                const std::optional<std::wstring> boundedObjectId =
                    CopyBoundedWideString(ids[index], kMaximumWpdIdentifierLength);
                if (!boundedObjectId.has_value()) {
                    ++catalog.propertyFailures;
                    CoTaskMemFree(ids[index]);
                    ids[index] = nullptr;
                    continue;
                }

                CatalogEntry entry;
                entry.objectId = *boundedObjectId;
                entry.depth = parent.childDepth;
                ++catalog.objectsVisited;

                ComPtr<IPortableDeviceValues> values;
                const HRESULT propertyResult = properties->GetValues(ids[index], keys.Get(), &values);
                if (propertyResult == S_OK && values.Get() != nullptr) {
                    entry.name = Truncate(GetOptionalString(values.Get(), WPD_OBJECT_NAME).value_or(L""), kMaximumDisplayString);
                    entry.originalFilename = Truncate(
                        GetOptionalString(values.Get(), WPD_OBJECT_ORIGINAL_FILE_NAME).value_or(L""),
                        kMaximumDisplayString);
                    entry.parentId = GetOptionalString(values.Get(), WPD_OBJECT_PARENT_ID).value_or(L"");
                    entry.persistentId = GetOptionalString(values.Get(), WPD_OBJECT_PERSISTENT_UNIQUE_ID).value_or(L"");
                    entry.contentType = GetOptionalGuid(values.Get(), WPD_OBJECT_CONTENT_TYPE);
                    entry.format = GetOptionalGuid(values.Get(), WPD_OBJECT_FORMAT);
                    entry.size = GetOptionalUnsignedLarge(values.Get(), WPD_OBJECT_SIZE);
                    entry.width = GetOptionalUnsigned(values.Get(), WPD_MEDIA_WIDTH);
                    entry.height = GetOptionalUnsigned(values.Get(), WPD_MEDIA_HEIGHT);
                    entry.dateCreated = GetOptionalDate(values.Get(), WPD_OBJECT_DATE_CREATED);
                } else {
                    ++catalog.propertyFailures;
                    if (propertyResult == S_FALSE) {
                        ++catalog.propertySFalseResults;
                    }
                }

                const std::wstring_view displayName = entry.name.empty()
                    ? std::wstring_view(entry.originalFilename)
                    : std::wstring_view(entry.name);
                entry.pathHint = JoinPathHint(parent.pathHint, displayName);
                const bool contentSaysImage = entry.contentType.has_value() &&
                    IsEqualGUID(*entry.contentType, WPD_CONTENT_TYPE_IMAGE);
                entry.isImage = contentSaysImage || HasImageExtension(entry.originalFilename) ||
                    HasImageExtension(entry.name);
                entry.isDcimLike = ContainsInsensitive(entry.pathHint, L"dcim") ||
                    ContainsInsensitive(entry.pathHint, L"apple");

                // Traverse declared containers and objects whose content type
                // could not be read. Do not issue child-enumeration calls for
                // known media leaves.
                const bool knownContainer = entry.contentType.has_value() &&
                    (IsEqualGUID(*entry.contentType, WPD_CONTENT_TYPE_FOLDER) ||
                     IsEqualGUID(*entry.contentType, WPD_CONTENT_TYPE_FUNCTIONAL_OBJECT));
                const bool mayHaveChildren = knownContainer || !entry.contentType.has_value();
                if (entry.depth < maxDepth && mayHaveChildren) {
                    pending.push_back({entry.objectId, entry.pathHint, entry.depth + 1});
                } else if (entry.depth >= maxDepth && mayHaveChildren) {
                    catalog.depthLimitReached = true;
                }

                catalog.entries.push_back(std::move(entry));
                CoTaskMemFree(ids[index]);
                ids[index] = nullptr;
            }
            for (PWSTR id : ids) {
                CoTaskMemFree(id);
            }
        }
    }

    if (!pending.empty() || catalog.objectsVisited >= maxObjects) {
        catalog.objectLimitReached = true;
    }
    return catalog;
}

void AddObjectIdentifiers(
    JsonLine& line,
    const CatalogEntry& entry,
    const Options& options,
    const std::shared_ptr<ObjectReferences>& references) {
    const std::optional<uint64_t> reference = references->Reference(entry.objectId);
    if (!reference.has_value()) {
        line.Null("object_ref");
    } else {
        line.String("object_ref", "object-" + std::to_string(*reference));
    }
    line.Boolean("object_ref_limit_reached", references->LimitReached())
        .Boolean("raw_ids_included", options.showIds);
    if (options.showIds) {
        line.WideString("object_id", entry.objectId);
        if (entry.persistentId.empty()) {
            line.Null("persistent_id");
        } else {
            line.WideString("persistent_id", entry.persistentId);
        }
        if (!entry.parentId.empty()) {
            line.WideString("parent_id", entry.parentId);
        }
    }
}

void EmitCatalogEntry(
    std::string eventName,
    const DeviceInfo& info,
    const CatalogEntry& entry,
    const Options& options,
    const std::shared_ptr<ObjectReferences>& references,
    const std::shared_ptr<JsonEmitter>& emitter) {
    auto line = EventLine(std::move(eventName));
    line.String("device_ref", info.Reference())
        .String("content_type", ContentTypeName(entry.contentType))
        .String("format", FormatName(entry.format))
        .Boolean("is_image", entry.isImage)
        .Boolean("is_dcim_like", entry.isDcimLike)
        .Boolean("metadata_included", options.showMetadata);
    if (options.showMetadata) {
        line.Number("depth", entry.depth)
            .WideString("name", entry.name)
            .WideString("original_filename", entry.originalFilename)
            .WideString("path_hint", entry.pathHint);
        if (entry.contentType.has_value()) {
            line.String("content_type_id", GuidString(*entry.contentType));
        }
        if (entry.format.has_value()) {
            line.String("format_id", GuidString(*entry.format));
        }
        if (entry.size.has_value()) {
            line.Number("size_bytes", *entry.size);
        } else {
            line.Null("size_bytes");
        }
        if (entry.width.has_value()) {
            line.Number("width", *entry.width);
        } else {
            line.Null("width");
        }
        if (entry.height.has_value()) {
            line.Number("height", *entry.height);
        } else {
            line.Null("height");
        }
        if (entry.dateCreated.has_value()) {
            line.String("date_created_timezone_unspecified", *entry.dateCreated);
        } else {
            line.Null("date_created_timezone_unspecified");
        }
    }
    AddObjectIdentifiers(line, entry, options, references);
    emitter->Emit(line);
}

struct OutputBudget {
    size_t objectDetailRecords = 0;
    size_t eventRecords = 0;
    bool objectLimitReported = false;
    bool eventLimitReported = false;
    bool queueOverflowReported = false;
    size_t totalDroppedEvents = 0;
};

bool ConsumeObjectDetailBudget(
    OutputBudget& budget,
    const DeviceInfo& info,
    const std::shared_ptr<JsonEmitter>& emitter) {
    if (budget.objectDetailRecords < kMaximumObjectDetailRecords) {
        ++budget.objectDetailRecords;
        return true;
    }
    if (!budget.objectLimitReported) {
        budget.objectLimitReported = true;
        auto line = EventLine("output_record_limit_reached");
        line.String("device_ref", info.Reference())
            .String("record_type", "object_detail")
            .Number("limit", kMaximumObjectDetailRecords);
        emitter->Emit(line);
    }
    return false;
}

std::unordered_set<std::wstring> EmitInitialCatalog(
    const DeviceInfo& info,
    const CatalogResult& catalog,
    const Options& options,
    const std::shared_ptr<ObjectReferences>& references,
    const std::shared_ptr<JsonEmitter>& emitter,
    OutputBudget& outputBudget) {
    std::unordered_set<std::wstring> identities;
    identities.reserve(catalog.entries.size());
    uint64_t interestingCount = 0;
    uint64_t imageCount = 0;
    for (const CatalogEntry& entry : catalog.entries) {
        identities.insert(entry.Identity());
        if (!entry.IsInteresting()) {
            continue;
        }
        ++interestingCount;
        if (entry.isImage) {
            ++imageCount;
        }
        if (options.showMetadata &&
            ConsumeObjectDetailBudget(outputBudget, info, emitter)) {
            EmitCatalogEntry("catalog_object", info, entry, options, references, emitter);
        }
    }

    auto line = EventLine("catalog_summary");
    line.String("device_ref", info.Reference())
        .Number("objects_visited", catalog.objectsVisited)
        .Number("objects_reported", interestingCount)
        .Number("images_reported", imageCount)
        .Boolean("baseline_object_details_emitted", options.showMetadata)
        .Number("property_failures", catalog.propertyFailures)
        .Number("property_s_false_results", catalog.propertySFalseResults)
        .Boolean("depth_limit_reached", catalog.depthLimitReached)
        .Boolean("object_limit_reached", catalog.objectLimitReached)
        .Number("max_depth", options.maxDepth)
        .Number("max_objects", options.maxObjects);
    if (catalog.fatalHresult.has_value()) {
        line.String("fatal_stage", catalog.fatalStage)
            .String("fatal_hresult", HResultString(*catalog.fatalHresult));
    } else {
        line.Null("fatal_stage").Null("fatal_hresult");
    }
    emitter->Emit(line);
    return identities;
}

void EmitNewCatalogObjects(
    const DeviceInfo& info,
    const CatalogResult& catalog,
    std::unordered_set<std::wstring>& knownIdentities,
    const Options& options,
    const std::shared_ptr<ObjectReferences>& references,
    const std::shared_ptr<JsonEmitter>& emitter,
    std::string_view scanReason,
    size_t maximumKnownIdentities,
    OutputBudget& outputBudget) {
    uint64_t newCount = 0;
    uint64_t newInterestingCount = 0;
    uint64_t untrackedDueToLimit = 0;
    for (const CatalogEntry& entry : catalog.entries) {
        const std::wstring identity = entry.Identity();
        if (knownIdentities.contains(identity)) {
            continue;
        }
        if (knownIdentities.size() >= maximumKnownIdentities) {
            ++untrackedDueToLimit;
            continue;
        }
        knownIdentities.insert(identity);
        ++newCount;
        if (entry.IsInteresting()) {
            ++newInterestingCount;
            if (ConsumeObjectDetailBudget(outputBudget, info, emitter)) {
                EmitCatalogEntry("new_catalog_object", info, entry, options, references, emitter);
            }
        }
    }

    auto line = EventLine("rescan_summary");
    line.String("device_ref", info.Reference())
        .String("reason", std::string(scanReason))
        .Number("objects_visited", catalog.objectsVisited)
        .Number("new_objects", newCount)
        .Number("new_interesting_objects", newInterestingCount)
        .Number("identities_untracked_due_to_limit", untrackedDueToLimit)
        .Number("known_identity_limit", maximumKnownIdentities)
        .Number("property_failures", catalog.propertyFailures)
        .Number("property_s_false_results", catalog.propertySFalseResults)
        .Boolean("depth_limit_reached", catalog.depthLimitReached)
        .Boolean("object_limit_reached", catalog.objectLimitReached);
    if (catalog.fatalHresult.has_value()) {
        line.String("fatal_stage", catalog.fatalStage)
            .String("fatal_hresult", HResultString(*catalog.fatalHresult));
    } else {
        line.Null("fatal_stage").Null("fatal_hresult");
    }
    emitter->Emit(line);
}

class PortableDeviceEventCallback final : public IPortableDeviceEventCallback {
public:
    PortableDeviceEventCallback(
        bool captureSensitiveIds,
        std::shared_ptr<BoundedEventQueue> queue)
        : captureSensitiveIds_(captureSensitiveIds),
          queue_(std::move(queue)) {}

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID interfaceId, void** object) override {
        if (object == nullptr) {
            return E_POINTER;
        }
        *object = nullptr;
        if (IsEqualIID(interfaceId, IID_IUnknown) ||
            IsEqualIID(interfaceId, IID_IPortableDeviceEventCallback)) {
            *object = static_cast<IPortableDeviceEventCallback*>(this);
            AddRef();
            return S_OK;
        }
        return E_NOINTERFACE;
    }

    ULONG STDMETHODCALLTYPE AddRef() override {
        return referenceCount_.fetch_add(1, std::memory_order_relaxed) + 1;
    }

    ULONG STDMETHODCALLTYPE Release() override {
        const ULONG remaining = referenceCount_.fetch_sub(1, std::memory_order_acq_rel) - 1;
        if (remaining == 0) {
            delete this;
        }
        return remaining;
    }

    HRESULT STDMETHODCALLTYPE OnEvent(IPortableDeviceValues* parameters) override {
        if (parameters == nullptr) {
            return E_POINTER;
        }

        QueuedWpdEvent record;
        record.eventIdResult = parameters->GetGuidValue(
            WPD_EVENT_PARAMETER_EVENT_ID,
            &record.eventId);
        record.hierarchyChangedResult = parameters->GetBoolValue(
            WPD_EVENT_PARAMETER_CHILD_HIERARCHY_CHANGED,
            &record.hierarchyChanged);

        auto copyBounded = [&](std::optional<std::wstring> value, std::wstring& destination) {
            if (!value.has_value()) {
                return;
            }
            if (value->size() > kMaximumEventIdentifierLength) {
                value->resize(kMaximumEventIdentifierLength);
                record.identifierTruncated = true;
            }
            destination = std::move(*value);
        };
        copyBounded(GetOptionalString(parameters, WPD_OBJECT_ID), record.objectId);
        if (captureSensitiveIds_) {
            copyBounded(GetOptionalString(parameters, WPD_OBJECT_PARENT_ID), record.parentId);
            copyBounded(
                GetOptionalString(
                    parameters,
                    WPD_EVENT_PARAMETER_OBJECT_PARENT_PERSISTENT_UNIQUE_ID),
                record.parentPersistentId);
        }

        queue_->Push(std::move(record));
        return S_OK;
    }

private:
    ~PortableDeviceEventCallback() = default;

    std::atomic<ULONG> referenceCount_{1};
    bool captureSensitiveIds_;
    std::shared_ptr<BoundedEventQueue> queue_;
};

bool ProcessEventDrain(
    EventDrain drain,
    const DeviceInfo& info,
    const Options& options,
    const std::shared_ptr<ObjectReferences>& references,
    const std::shared_ptr<JsonEmitter>& emitter,
    OutputBudget& outputBudget) {
    if (drain.droppedRecords != 0) {
        outputBudget.totalDroppedEvents += drain.droppedRecords;
        if (!outputBudget.queueOverflowReported) {
            outputBudget.queueOverflowReported = true;
            auto overflow = EventLine("event_queue_overflow");
            overflow.String("device_ref", info.Reference())
                .Number("queue_capacity", kMaximumQueuedEvents)
                .Number("dropped_records_so_far", outputBudget.totalDroppedEvents);
            emitter->Emit(overflow);
        }
    }

    bool requestsRescan = false;
    for (const QueuedWpdEvent& record : drain.records) {
        const bool eventAvailable = record.eventIdResult == S_OK;
        const bool hierarchyAvailable = record.hierarchyChangedResult == S_OK;
        if (eventAvailable &&
            (IsEqualGUID(record.eventId, WPD_EVENT_OBJECT_ADDED) ||
             IsEqualGUID(record.eventId, WPD_EVENT_OBJECT_UPDATED))) {
            requestsRescan = true;
        }
        if (hierarchyAvailable && record.hierarchyChanged == TRUE) {
            requestsRescan = true;
        }

        if (outputBudget.eventRecords >= kMaximumEventRecords) {
            if (!outputBudget.eventLimitReported) {
                outputBudget.eventLimitReported = true;
                auto limit = EventLine("output_record_limit_reached");
                limit.String("device_ref", info.Reference())
                    .String("record_type", "wpd_event")
                    .Number("limit", kMaximumEventRecords);
                emitter->Emit(limit);
            }
            continue;
        }
        ++outputBudget.eventRecords;

        auto line = EventLine("wpd_event");
        line.String("device_ref", info.Reference())
            .Boolean("event_id_available", eventAvailable)
            .String("event_id_hresult", HResultString(record.eventIdResult))
            .Boolean("child_hierarchy_changed_available", hierarchyAvailable)
            .String("child_hierarchy_changed_hresult", HResultString(record.hierarchyChangedResult))
            .Boolean("child_hierarchy_changed", hierarchyAvailable && record.hierarchyChanged == TRUE)
            .Boolean("event_identifier_truncated", record.identifierTruncated)
            .Boolean("raw_ids_included", options.showIds);
        if (eventAvailable) {
            line.String("event_name", KnownEventName(record.eventId))
                .String("event_id", GuidString(record.eventId));
        } else {
            line.String("event_name", "UNAVAILABLE");
        }

        if (!record.objectId.empty()) {
            const std::optional<uint64_t> reference = references->Reference(record.objectId);
            if (reference.has_value()) {
                line.String("object_ref", "object-" + std::to_string(*reference));
            } else {
                line.Null("object_ref");
            }
            if (options.showIds) {
                line.WideString("object_id", record.objectId);
            }
        } else {
            line.Null("object_ref");
        }
        line.Boolean("object_ref_limit_reached", references->LimitReached());
        if (options.showIds && !record.parentId.empty()) {
            line.WideString("parent_id", record.parentId);
        }
        if (options.showIds && !record.parentPersistentId.empty()) {
            line.WideString("parent_persistent_id", record.parentPersistentId);
        }
        emitter->Emit(line);
    }
    return requestsRescan;
}

bool ProbeDevice(
    const DeviceInfo& info,
    const Options& options,
    const std::shared_ptr<JsonEmitter>& emitter) {
    auto opening = EventLine("device_open_start");
    opening.String("device_ref", info.Reference())
        .Boolean("read_only_requested", true);
    emitter->Emit(opening);

    ComPtr<IPortableDevice> device;
    const HRESULT openResult = OpenReadOnly(info, device);
    if (openResult != S_OK || device.Get() == nullptr) {
        auto failure = EventLine("device_open_error");
        failure.String("device_ref", info.Reference())
            .String("hresult", HResultString(openResult))
            .Boolean("read_only_requested", true);
        emitter->Emit(failure);
        return false;
    }

    auto opened = EventLine("device_opened");
    opened.String("device_ref", info.Reference())
        .Boolean("read_only_requested", true);
    emitter->Emit(opened);

    const SupportedEventSummary eventSummary = ReportSupportedEvents(device.Get(), info, emitter);
    const size_t maximumTrackedIdentities = std::min<size_t>(
        static_cast<size_t>(options.maxObjects) * 2,
        100'000);
    const auto references = std::make_shared<ObjectReferences>(maximumTrackedIdentities);
    const auto eventQueue = std::make_shared<BoundedEventQueue>();
    OutputBudget outputBudget;

    // Snapshot A precedes Advise. Snapshot B below follows Advise, closing the
    // otherwise unavoidable baseline/subscription race without classifying
    // all pre-existing content as new.
    const CatalogResult snapshotA = BuildCatalog(
        device.Get(),
        options.maxDepth,
        options.maxObjects);
    std::unordered_set<std::wstring> knownIdentities = EmitInitialCatalog(
        info,
        snapshotA,
        options,
        references,
        emitter,
        outputBudget);

    ComPtr<PortableDeviceEventCallback> callback;
    callback.Attach(new PortableDeviceEventCallback(
        options.showIds,
        eventQueue));

    PWSTR eventCookie = nullptr;
    const HRESULT adviseResult = device->Advise(0, callback.Get(), nullptr, &eventCookie);
    const bool nullCookieOnSuccess = adviseResult == S_OK && eventCookie == nullptr;
    const bool subscribed = adviseResult == S_OK && eventCookie != nullptr;
    const HRESULT effectiveAdviseResult = nullCookieOnSuccess ? E_UNEXPECTED : adviseResult;
    auto subscription = EventLine(subscribed ? "event_subscription_started" : "event_subscription_error");
    subscription.String("device_ref", info.Reference())
        .Boolean("subscribed", subscribed)
        .String("hresult", HResultString(effectiveAdviseResult))
        .String("raw_advise_hresult", HResultString(adviseResult))
        .Boolean("null_cookie_on_s_ok", nullCookieOnSuccess)
        .Boolean("supported_events_query_succeeded", eventSummary.querySucceeded)
        .Boolean("object_added_advertised", eventSummary.objectAddedAdvertised)
        .Boolean("object_added_broadcast", eventSummary.objectAddedBroadcast);
    emitter->Emit(subscription);

    const CatalogResult snapshotB = BuildCatalog(
        device.Get(),
        options.maxDepth,
        options.maxObjects);
    EmitNewCatalogObjects(
        info,
        snapshotB,
        knownIdentities,
        options,
        references,
        emitter,
        "post_subscribe_gap_check",
        maximumTrackedIdentities,
        outputBudget);

    EventDrain preObservationEvents = eventQueue->DrainUntil(std::chrono::steady_clock::now());
    bool pendingEventScan = ProcessEventDrain(
        std::move(preObservationEvents),
        info,
        options,
        references,
        emitter,
        outputBudget);

    const auto observationStart = std::chrono::steady_clock::now();
    const auto observationEnd = observationStart + std::chrono::seconds(options.observeSeconds);
    auto nextPoll = options.pollSeconds == 0
        ? observationEnd
        : observationStart + std::chrono::seconds(options.pollSeconds);

    auto startLine = EventLine("observation_started");
    startLine.String("device_ref", info.Reference())
        .Number("observe_seconds", options.observeSeconds)
        .Number("poll_interval_seconds", options.pollSeconds)
        .Boolean("event_subscription_active", subscribed)
        .String("baseline_sequence", "snapshot_a_advise_snapshot_b");
    emitter->Emit(startLine);

    size_t eventDrivenRescans = 0;
    bool eventRescanLimitReported = false;
    while (std::chrono::steady_clock::now() < observationEnd) {
        const auto wakeAt = std::min(observationEnd, nextPoll);
        EventDrain drain = eventQueue->DrainUntil(
            pendingEventScan ? std::chrono::steady_clock::now() : wakeAt);
        const bool drainedEventRequestedScan = ProcessEventDrain(
            std::move(drain),
            info,
            options,
            references,
            emitter,
            outputBudget);
        bool eventRequestedScan = pendingEventScan || drainedEventRequestedScan;
        pendingEventScan = false;
        const auto afterWait = std::chrono::steady_clock::now();
        if (afterWait >= observationEnd && !eventRequestedScan) {
            break;
        }

        const bool timerRequestedScan = options.pollSeconds != 0 && afterWait >= nextPoll;
        if (!eventRequestedScan && !timerRequestedScan) {
            continue;
        }
        if (timerRequestedScan) {
            nextPoll = afterWait + std::chrono::seconds(options.pollSeconds);
        }
        if (eventRequestedScan && eventDrivenRescans >= kMaximumEventDrivenRescans) {
            eventRequestedScan = false;
            if (!eventRescanLimitReported) {
                eventRescanLimitReported = true;
                auto limit = EventLine("event_rescan_limit_reached");
                limit.String("device_ref", info.Reference())
                    .Number("limit", kMaximumEventDrivenRescans);
                emitter->Emit(limit);
            }
        }
        if (eventRequestedScan) {
            ++eventDrivenRescans;
        }
        if (!eventRequestedScan && !timerRequestedScan) {
            continue;
        }

        const CatalogResult catalog = BuildCatalog(device.Get(), options.maxDepth, options.maxObjects);
        EmitNewCatalogObjects(
            info,
            catalog,
            knownIdentities,
            options,
            references,
            emitter,
            eventRequestedScan ? "wpd_event" : "poll_timer",
            maximumTrackedIdentities,
            outputBudget);
    }

    if (eventCookie != nullptr) {
        const HRESULT unadviseResult = device->Unadvise(eventCookie);
        auto line = EventLine(subscribed && unadviseResult == S_OK
            ? "event_subscription_stopped"
            : "event_unsubscribe_error");
        line.String("device_ref", info.Reference())
            .String("hresult", HResultString(unadviseResult));
        emitter->Emit(line);
    }
    CoTaskMemFree(eventCookie);
    eventCookie = nullptr;

    ProcessEventDrain(
        eventQueue->DrainUntil(std::chrono::steady_clock::now()),
        info,
        options,
        references,
        emitter,
        outputBudget);

    auto finished = EventLine("observation_finished");
    const bool catalogPathCompleted = !snapshotA.fatalHresult.has_value() ||
        !snapshotB.fatalHresult.has_value();
    const bool minimumPathCompleted = eventSummary.querySucceeded && catalogPathCompleted;
    finished.String("device_ref", info.Reference())
        .Boolean("minimum_capability_catalog_path_completed", minimumPathCompleted)
        .Number("event_records_emitted", outputBudget.eventRecords)
        .Number("object_records_emitted", outputBudget.objectDetailRecords)
        .Number("event_records_dropped", outputBudget.totalDroppedEvents)
        .Number("event_driven_rescans", eventDrivenRescans)
        .Boolean("object_ref_limit_reached", references->LimitReached());
    emitter->Emit(finished);

    device->Close();
    return minimumPathCompleted;
}

} // namespace

int wmain(int argc, wchar_t** argv) {
    SetConsoleOutputCP(CP_UTF8);

    Options options;
    std::wstring optionError;
    if (!ParseOptions(argc, argv, options, optionError)) {
        JsonEmitter emitter;
        auto line = EventLine("argument_error");
        line.WideString("message", optionError);
        emitter.Emit(line);
        return 2;
    }
    if (options.help) {
        PrintUsage();
        return 0;
    }

    const auto emitter = std::make_shared<JsonEmitter>();
    auto start = EventLine("probe_started");
    start.Number("schema_version", kSchemaVersion)
        .String("probe_scope", "phase_1_metadata_only")
        .Boolean("read_only", true)
        .Boolean("metadata_included", options.showMetadata)
        .Boolean("raw_ids_included", options.showIds)
        .Number("observe_seconds", options.observeSeconds)
        .Number("poll_interval_seconds", options.pollSeconds)
        .Number("max_depth", options.maxDepth)
        .Number("max_objects", options.maxObjects);
    emitter->Emit(start);

    ComApartment apartment;
    if (FAILED(apartment.Result())) {
        auto line = EventLine("com_initialization_error");
        line.String("hresult", HResultString(apartment.Result()));
        emitter->Emit(line);
        return 1;
    }

    ComPtr<IPortableDeviceManager> manager;
    HRESULT result = CoCreateInstance(
        CLSID_PortableDeviceManager,
        nullptr,
        CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&manager));
    if (FAILED(result)) {
        auto line = EventLine("device_manager_error");
        line.String("hresult", HResultString(result));
        emitter->Emit(line);
        return 1;
    }

    result = manager->RefreshDeviceList();
    if (FAILED(result)) {
        auto line = EventLine("device_refresh_error");
        line.String("hresult", HResultString(result));
        emitter->Emit(line);
    }

    std::vector<DeviceInfo> devices;
    result = EnumerateDevices(manager.Get(), devices);
    if (result != S_OK) {
        auto line = EventLine("device_enumeration_error");
        line.String("hresult", HResultString(result));
        emitter->Emit(line);
        return 1;
    }

    size_t candidateCount = 0;
    size_t selectedCount = 0;
    for (const DeviceInfo& device : devices) {
        if (device.appleCandidate) {
            ++candidateCount;
        }
        const bool indexSelected = !options.deviceIndex.has_value() ||
            *options.deviceIndex == device.index;
        const bool selected = options.deviceIndex.has_value()
            ? indexSelected
            : (device.appleCandidate || options.includeAllDevices);
        if (selected) {
            ++selectedCount;
        }

        auto line = EventLine("device_discovered");
        line.Number("device_index", device.index)
            .String("device_ref", device.Reference())
            .Boolean("apple_candidate", device.appleCandidate)
            .Boolean("selected_for_probe", selected)
            .Boolean("metadata_included", options.showMetadata)
            .Boolean("raw_ids_included", options.showIds);
        if (options.showMetadata) {
            line.WideString("friendly_name", device.friendlyName)
                .WideString("manufacturer", device.manufacturer)
                .WideString("description", device.description);
        }
        if (options.showIds) {
            line.WideString("pnp_device_id", device.pnpId);
        }
        emitter->Emit(line);
    }

    auto summary = EventLine("device_enumeration_summary");
    summary.Number("device_count", devices.size())
        .Number("apple_candidate_count", candidateCount)
        .Number("selected_device_count", selectedCount)
        .Boolean("candidate_detection_is_heuristic", true);
    if (candidateCount == 0 && !devices.empty()) {
        summary.String("selection_hint", "rerun with --show-metadata, then select an index explicitly");
    }
    emitter->Emit(summary);

    if (options.deviceIndex.has_value()) {
        const bool found = std::any_of(devices.begin(), devices.end(), [&](const DeviceInfo& device) {
            return device.index == *options.deviceIndex;
        });
        if (!found) {
            auto line = EventLine("selected_device_not_found");
            line.Number("device_index", *options.deviceIndex);
            emitter->Emit(line);
            return 3;
        }
    }

    size_t completedCount = 0;
    for (const DeviceInfo& device : devices) {
        const bool indexSelected = !options.deviceIndex.has_value() ||
            *options.deviceIndex == device.index;
        const bool selected = options.deviceIndex.has_value()
            ? indexSelected
            : (device.appleCandidate || options.includeAllDevices);
        if (!selected) {
            continue;
        }
        if (ProbeDevice(device, options, emitter)) {
            ++completedCount;
        }
    }

    auto finished = EventLine("probe_finished");
    finished.Number("selected_device_count", selectedCount)
        .Number("completed_minimum_path_count", completedCount);
    emitter->Emit(finished);
    if (selectedCount == 0) {
        return 4;
    }
    return completedCount == 0 ? 5 : 0;
}
