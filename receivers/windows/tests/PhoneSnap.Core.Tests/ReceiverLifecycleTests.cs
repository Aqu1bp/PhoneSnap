using System.Net;
using PhoneSnap.Core.Images;
using PhoneSnap.Core.Pairing;
using PhoneSnap.Core.Receiver;

namespace PhoneSnap.Core.Tests;

public sealed class ReceiverLifecycleTests
{
    private static readonly PairingCredentials Pairing = new(
        "AbCdEf0123-_",
        "0123456789abcdefghijklmnopqrstuvwxyzABCDE_g");

    [Fact]
    public async Task StopQueuedDuringStartLeavesNoRunningListener()
    {
        using var temporary = new TemporaryDirectory();
        await using var receiver = CreateReceiver(temporary.Path, advertisedHost: "127.0.0.1");

        var start = receiver.StartAsync();
        var stop = receiver.StopAsync();
        await Task.WhenAll(start, stop);

        Assert.Equal(ReceiverActivity.Stopped, receiver.State.Activity);
        Assert.Equal(0, receiver.BoundPort);
        Assert.Null(receiver.BaseUri);
    }

    [Fact]
    public async Task AdvertisedAddressCanAppearChangeAndDisappearAtRuntime()
    {
        using var temporary = new TemporaryDirectory();
        await using var receiver = CreateReceiver(temporary.Path, advertisedHost: null);
        await receiver.StartAsync();
        var port = receiver.BoundPort;

        Assert.True(port > 0);
        Assert.Null(receiver.SetupUri);

        receiver.UpdateAdvertisedHost("127.0.0.1");
        Assert.Equal(port, receiver.BaseUri?.Port);
        Assert.Equal("127.0.0.1", receiver.BaseUri?.Host);

        receiver.UpdateAdvertisedHost(null);
        Assert.Null(receiver.BaseUri);
        Assert.Null(receiver.SetupUri);
    }

    private static ReceiverServer CreateReceiver(string folder, string? advertisedHost)
    {
        return new ReceiverServer(
            new ReceiverOptions
            {
                ListenAddress = IPAddress.Loopback,
                Port = 0,
                AdvertisedHost = advertisedHost,
            },
            Pairing,
            new ImageStore(folder, new ValidatingNormalizer()));
    }
}
