using System.Net;

namespace PhoneSnap.Core.Receiver;

public sealed record ReceiverOptions
{
    public const int ProtocolMaximumBodyBytes = 32 * 1024 * 1024;

    public IPAddress ListenAddress { get; init; } = IPAddress.Any;

    public int Port { get; init; } = 8472;

    public string AdvertisedHost { get; init; } = "127.0.0.1";

    public int MaximumBodyBytes { get; init; } = ProtocolMaximumBodyBytes;

    public int MaximumPixelCount { get; init; } = 50_000_000;

    public TimeSpan HeaderTimeout { get; init; } = TimeSpan.FromSeconds(5);

    public TimeSpan RequestTimeout { get; init; } = TimeSpan.FromSeconds(30);

    public TimeSpan KeepAliveTimeout { get; init; } = TimeSpan.FromSeconds(5);

    public int MaximumConcurrentConnections { get; init; } = 4;

    internal void Validate()
    {
        ArgumentNullException.ThrowIfNull(ListenAddress);
        ArgumentException.ThrowIfNullOrWhiteSpace(AdvertisedHost);
        if (Port is < 0 or > 65_535)
        {
            throw new ArgumentOutOfRangeException(nameof(Port));
        }

        if (MaximumBodyBytes is <= 0 or > ProtocolMaximumBodyBytes)
        {
            throw new ArgumentOutOfRangeException(nameof(MaximumBodyBytes));
        }

        if (MaximumPixelCount <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(MaximumPixelCount));
        }

        if (HeaderTimeout <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(HeaderTimeout));
        }

        if (RequestTimeout <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(RequestTimeout));
        }

        if (KeepAliveTimeout <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(KeepAliveTimeout));
        }

        if (MaximumConcurrentConnections <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(MaximumConcurrentConnections));
        }
    }
}
