using System.Net;

namespace PhoneSnap.Core.Networking;

public enum LanInterfaceKind
{
    Other,
    Ethernet,
    Wireless,
}

public sealed record LanAddressCandidate(
    IPAddress Address,
    string InterfaceName,
    LanInterfaceKind InterfaceKind,
    bool HasGateway,
    uint? EffectiveRouteMetric,
    bool IsLikelyVirtual);

public static class LanAddressRanking
{
    public static IReadOnlyList<LanAddressCandidate> Rank(IEnumerable<LanAddressCandidate> candidates)
    {
        ArgumentNullException.ThrowIfNull(candidates);

        return candidates
            .OrderBy(candidate => candidate.IsLikelyVirtual)
            .ThenByDescending(candidate => IsPrivateIPv4(candidate.Address))
            .ThenBy(candidate => IsSuitableLanKind(candidate.InterfaceKind) ? 0 : 1)
            .ThenByDescending(candidate => candidate.HasGateway)
            .ThenBy(candidate => candidate.EffectiveRouteMetric ?? uint.MaxValue)
            .ThenBy(candidate => candidate.InterfaceName, StringComparer.OrdinalIgnoreCase)
            .ThenBy(candidate => candidate.Address.ToString(), StringComparer.Ordinal)
            .DistinctBy(candidate => candidate.Address)
            .ToArray();
    }

    public static IPAddress? SelectPreferredAddress(
        IReadOnlyList<LanAddressCandidate> rankedCandidates,
        IPAddress? currentAddress)
    {
        ArgumentNullException.ThrowIfNull(rankedCandidates);

        if (currentAddress is not null)
        {
            foreach (var candidate in rankedCandidates)
            {
                if (candidate.Address.Equals(currentAddress))
                {
                    return candidate.Address;
                }
            }
        }

        return rankedCandidates.Count > 0 ? rankedCandidates[0].Address : null;
    }

    private static bool IsSuitableLanKind(LanInterfaceKind kind) =>
        kind is LanInterfaceKind.Ethernet or LanInterfaceKind.Wireless;

    private static bool IsPrivateIPv4(IPAddress address)
    {
        var bytes = address.GetAddressBytes();
        return bytes is [10, _, _, _] ||
               bytes is [192, 168, _, _] ||
               (bytes is [172, >= 16 and <= 31, _, _]);
    }
}
