using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using PhoneSnap.Core.Networking;

namespace PhoneSnap.Windows.Platform;

internal static class LanAddressProvider
{
    private static readonly string[] VirtualAdapterMarkers =
    [
        "virtual",
        "hyper-v",
        "vmware",
        "virtualbox",
        "vpn",
        "wireguard",
        "tailscale",
        "zerotier",
        "docker",
        "wsl",
        "tap-",
        "tap ",
        "tun ",
    ];

    public static IPAddress? GetPreferredIPv4()
    {
        var candidates = GetRankedIPv4Candidates();
        return candidates.Count > 0 ? candidates[0].Address : null;
    }

    public static IReadOnlyList<LanAddressCandidate> GetRankedIPv4Candidates()
    {
        IReadOnlyDictionary<int, uint> effectiveRouteMetrics;
        try
        {
            effectiveRouteMetrics = WindowsRouteMetricProvider.GetEffectiveDefaultRouteMetrics();
        }
        catch (NetworkInformationException)
        {
            effectiveRouteMetrics = new Dictionary<int, uint>();
        }

        var candidates = new List<LanAddressCandidate>();
        foreach (var network in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (network.OperationalStatus != OperationalStatus.Up ||
                network.NetworkInterfaceType is NetworkInterfaceType.Loopback or NetworkInterfaceType.Tunnel)
            {
                continue;
            }

            IPInterfaceProperties properties;
            IPv4InterfaceProperties? ipv4Properties;
            try
            {
                properties = network.GetIPProperties();
                ipv4Properties = properties.GetIPv4Properties();
            }
            catch (NetworkInformationException)
            {
                continue;
            }

            if (ipv4Properties is null)
            {
                continue;
            }

            var hasGateway = properties.GatewayAddresses.Any(gateway =>
                gateway.Address.AddressFamily == AddressFamily.InterNetwork &&
                !IPAddress.Any.Equals(gateway.Address));
            uint? effectiveRouteMetric = effectiveRouteMetrics.TryGetValue(ipv4Properties.Index, out var routeMetric)
                ? routeMetric
                : null;
            var isLikelyVirtual = IsLikelyVirtual(network);
            var kind = MapKind(network.NetworkInterfaceType);

            foreach (var address in properties.UnicastAddresses.Select(entry => entry.Address).Where(IsUsableIPv4))
            {
                candidates.Add(new LanAddressCandidate(
                    address,
                    network.Name,
                    kind,
                    hasGateway,
                    effectiveRouteMetric,
                    isLikelyVirtual));
            }
        }

        return LanAddressRanking.Rank(candidates);
    }

    private static LanInterfaceKind MapKind(NetworkInterfaceType type) => type switch
    {
        NetworkInterfaceType.Wireless80211 => LanInterfaceKind.Wireless,
        NetworkInterfaceType.Ethernet or
            NetworkInterfaceType.FastEthernetFx or
            NetworkInterfaceType.FastEthernetT or
            NetworkInterfaceType.GigabitEthernet => LanInterfaceKind.Ethernet,
        _ => LanInterfaceKind.Other,
    };

    private static bool IsLikelyVirtual(NetworkInterface network)
    {
        var identity = $"{network.Name}\n{network.Description}";
        return VirtualAdapterMarkers.Any(marker => identity.Contains(marker, StringComparison.OrdinalIgnoreCase));
    }

    private static bool IsUsableIPv4(IPAddress address)
    {
        if (address.AddressFamily != AddressFamily.InterNetwork ||
            IPAddress.IsLoopback(address) ||
            IPAddress.Any.Equals(address))
        {
            return false;
        }

        var bytes = address.GetAddressBytes();
        return bytes is not [169, 254, _, _] && bytes[0] is > 0 and < 224;
    }
}

internal static class WindowsRouteMetricProvider
{
    private const uint ErrorSuccess = 0;
    private const uint ErrorInsufficientBuffer = 122;
    private const uint ErrorNoData = 232;

    public static IReadOnlyDictionary<int, uint> GetEffectiveDefaultRouteMetrics()
    {
        // GetIpForwardTable reports the effective IPv4 metric: route cost plus interface metric.
        uint requiredSize = 0;
        var result = GetIpForwardTable(IntPtr.Zero, ref requiredSize, order: false);
        if (result == ErrorNoData)
        {
            return new Dictionary<int, uint>();
        }

        if (result != ErrorInsufficientBuffer || requiredSize < sizeof(uint))
        {
            throw new NetworkInformationException(checked((int)result));
        }

        var buffer = Marshal.AllocHGlobal(checked((int)requiredSize));
        try
        {
            result = GetIpForwardTable(buffer, ref requiredSize, order: false);
            if (result != ErrorSuccess)
            {
                throw new NetworkInformationException(checked((int)result));
            }

            var entryCount = checked((uint)Marshal.ReadInt32(buffer));
            var rowSize = Marshal.SizeOf<MibIpForwardRow>();
            var availableRowBytes = requiredSize - sizeof(uint);
            if (entryCount > availableRowBytes / rowSize)
            {
                throw new NetworkInformationException();
            }

            var metrics = new Dictionary<int, uint>();
            for (var index = 0U; index < entryCount; index += 1)
            {
                var offset = checked(sizeof(uint) + ((int)index * rowSize));
                var row = Marshal.PtrToStructure<MibIpForwardRow>(IntPtr.Add(buffer, offset));
                if (row.Destination != 0 || row.Mask != 0 || row.Metric == uint.MaxValue ||
                    row.InterfaceIndex > int.MaxValue)
                {
                    continue;
                }

                var interfaceIndex = (int)row.InterfaceIndex;
                if (!metrics.TryGetValue(interfaceIndex, out var currentMetric) || row.Metric < currentMetric)
                {
                    metrics[interfaceIndex] = row.Metric;
                }
            }

            return metrics;
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }

    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [DllImport("iphlpapi.dll", ExactSpelling = true)]
    private static extern uint GetIpForwardTable(
        IntPtr table,
        ref uint size,
        [MarshalAs(UnmanagedType.Bool)] bool order);

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct MibIpForwardRow
    {
        public readonly uint Destination;
        public readonly uint Mask;
        public readonly uint Policy;
        public readonly uint NextHop;
        public readonly uint InterfaceIndex;
        public readonly uint Type;
        public readonly uint Protocol;
        public readonly uint Age;
        public readonly uint NextHopAutonomousSystem;
        public readonly uint Metric;
        public readonly uint Metric2;
        public readonly uint Metric3;
        public readonly uint Metric4;
        public readonly uint Metric5;
    }
}
