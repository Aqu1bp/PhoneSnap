cmake_minimum_required(VERSION 3.21)

project(PhoneSnapWpdProbe LANGUAGES CXX)

if(NOT WIN32)
    message(FATAL_ERROR "WpdProbe uses Windows Portable Devices COM APIs and can only be built on Windows.")
endif()

add_executable(WpdProbe main.cpp)
target_compile_features(WpdProbe PRIVATE cxx_std_20)
target_compile_definitions(WpdProbe PRIVATE
    UNICODE
    _UNICODE
    _WIN32_WINNT=0x0A00
    WIN32_LEAN_AND_MEAN
    NOMINMAX
)

if(MSVC)
    target_compile_options(WpdProbe PRIVATE /W4 /permissive- /EHsc /utf-8)
endif()

target_link_libraries(WpdProbe PRIVATE
    Ole32
    OleAut32
    PortableDeviceGUIDs
    Propsys
)
