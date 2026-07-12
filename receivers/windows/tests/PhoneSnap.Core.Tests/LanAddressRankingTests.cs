using System.Net;
using PhoneSnap.Core.Networking;

namespace PhoneSnap.Core.Tests;

public sealed class LanAddressRankingTests
{
    [Fact]
    public void PhysicalLanAdapterRanksAheadOfLowerMetricVirtualAdapter()
    {
        var vpn = Candidate(
            "10.8.0.2",
            "Contoso VPN",
            LanInterfaceKind.Ethernet,
            metric: 5,
            isLikelyVirtual: true);
        var wifi = Candidate(
            "192.168.1.24",
            "Wi-Fi",
            LanInterfaceKind.Wireless,
            metric: 35);

        var ranked = LanAddressRanking.Rank([vpn, wifi]);

        Assert.Equal(wifi, ranked[0]);
        Assert.Equal(vpn, ranked[1]);
    }

    [Fact]
    public void EffectiveWindowsRouteMetricBreaksPhysicalAdapterTie()
    {
        var slower = Candidate(
            "192.168.1.24",
            "Wi-Fi",
            LanInterfaceKind.Wireless,
            metric: 45);
        var preferred = Candidate(
            "192.168.1.25",
            "Ethernet",
            LanInterfaceKind.Ethernet,
            metric: 20);

        var ranked = LanAddressRanking.Rank([slower, preferred]);

        Assert.Equal(preferred, ranked[0]);
        Assert.Equal(slower, ranked[1]);
    }

    [Fact]
    public void PrivateLanAdapterWithGatewayRanksAheadOfFallbackAddress()
    {
        var fallback = Candidate(
            "203.0.113.8",
            "Unknown adapter",
            LanInterfaceKind.Other,
            hasGateway: false,
            metric: null);
        var ethernet = Candidate(
            "172.20.4.10",
            "Ethernet",
            LanInterfaceKind.Ethernet,
            metric: 30);

        var ranked = LanAddressRanking.Rank([fallback, ethernet]);

        Assert.Equal(ethernet, ranked[0]);
        Assert.Equal(fallback, ranked[1]);
    }

    [Fact]
    public void RankingIsDeterministicAndKeepsEveryDistinctChoice()
    {
        var wifi = Candidate("192.168.1.24", "Wi-Fi", LanInterfaceKind.Wireless, metric: 25);
        var duplicate = Candidate("192.168.1.24", "Wi-Fi alias", LanInterfaceKind.Wireless, metric: 50);
        var ethernet = Candidate("192.168.1.30", "Ethernet", LanInterfaceKind.Ethernet, metric: 25);

        var first = LanAddressRanking.Rank([wifi, duplicate, ethernet]);
        var second = LanAddressRanking.Rank([ethernet, duplicate, wifi]);

        Assert.Equal(first, second);
        Assert.Equal(2, first.Count);
        Assert.Equal([ethernet.Address, wifi.Address], first.Select(candidate => candidate.Address));
    }

    [Fact]
    public void CurrentExplicitChoiceIsPreservedWhileAddressRemainsAvailable()
    {
        var recommended = Candidate("192.168.1.24", "Wi-Fi", LanInterfaceKind.Wireless, metric: 10);
        var selected = Candidate("192.168.50.8", "Ethernet", LanInterfaceKind.Ethernet, metric: 40);
        var ranked = LanAddressRanking.Rank([recommended, selected]);

        var preserved = LanAddressRanking.SelectPreferredAddress(ranked, selected.Address);
        var fallback = LanAddressRanking.SelectPreferredAddress([recommended], selected.Address);

        Assert.Equal(selected.Address, preserved);
        Assert.Equal(recommended.Address, fallback);
    }

    private static LanAddressCandidate Candidate(
        string address,
        string interfaceName,
        LanInterfaceKind kind,
        bool hasGateway = true,
        uint? metric = 25,
        bool isLikelyVirtual = false) =>
        new(
            IPAddress.Parse(address),
            interfaceName,
            kind,
            hasGateway,
            metric,
            isLikelyVirtual);
}
