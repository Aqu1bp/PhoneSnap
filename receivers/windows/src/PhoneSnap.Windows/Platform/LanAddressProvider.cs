using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;

namespace PhoneSnap.Windows.Platform;

internal static class LanAddressProvider
{
    public static IPAddress GetPreferredIPv4()
    {
        var candidates = NetworkInterface.GetAllNetworkInterfaces()
            .Where(network => network.OperationalStatus == OperationalStatus.Up &&
                              network.NetworkInterfaceType is not NetworkInterfaceType.Loopback and
                                  not NetworkInterfaceType.Tunnel)
            .Select(network => new
            {
                HasGateway = network.GetIPProperties().GatewayAddresses.Any(gateway =>
                    gateway.Address.AddressFamily == AddressFamily.InterNetwork &&
                    !IPAddress.Any.Equals(gateway.Address)),
                Addresses = network.GetIPProperties().UnicastAddresses
                    .Select(address => address.Address)
                    .Where(IsUsableIPv4)
                    .ToArray(),
            })
            .OrderByDescending(candidate => candidate.HasGateway);

        return candidates.SelectMany(candidate => candidate.Addresses).FirstOrDefault()
            ?? IPAddress.Loopback;
    }

    private static bool IsUsableIPv4(IPAddress address)
    {
        if (address.AddressFamily != AddressFamily.InterNetwork || IPAddress.IsLoopback(address))
        {
            return false;
        }

        var bytes = address.GetAddressBytes();
        return bytes is not [169, 254, _, _] && !address.Equals(IPAddress.Any);
    }
}
