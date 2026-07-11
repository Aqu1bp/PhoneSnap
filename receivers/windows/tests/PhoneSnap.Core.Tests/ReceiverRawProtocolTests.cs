using System.Net;
using System.Net.Sockets;
using System.Text;
using PhoneSnap.Core.Images;
using PhoneSnap.Core.Pairing;
using PhoneSnap.Core.Receiver;

namespace PhoneSnap.Core.Tests;

public sealed class ReceiverRawProtocolTests : IAsyncLifetime, IDisposable
{
    private const string PairId = "AbCdEf0123-_";
    private const string Token = "0123456789abcdefghijklmnopqrstuvwxyzABCDE_g";
    private readonly TemporaryDirectory _temporary = new();
    private ReceiverServer? _server;

    public async Task InitializeAsync()
    {
        _server = new ReceiverServer(
            new ReceiverOptions
            {
                ListenAddress = IPAddress.Loopback,
                Port = 0,
                AdvertisedHost = "127.0.0.1",
            },
            new PairingCredentials(PairId, Token),
            new ImageStore(_temporary.Path, new ValidatingNormalizer()));
        await _server.StartAsync();
    }

    public async Task DisposeAsync()
    {
        if (_server is not null)
        {
            await _server.DisposeAsync();
        }
        Dispose();
    }

    public void Dispose() => _temporary.Dispose();

    [Theory]
    [InlineData("", "411")]
    [InlineData("Content-Length: 33554433\r\n", "413")]
    [InlineData("Content-Length: 1\r\nContent-Length: 1\r\n", "400")]
    public async Task EnforcesContentLengthRules(string lengthHeaders, string expectedStatus)
    {
        var response = await SendAndReadHeaderAsync(
            $"POST /api/v1/upload/{PairId} HTTP/1.1\r\n" +
            "Host: 127.0.0.1\r\n" +
            $"Authorization: Bearer {Token}\r\n" +
            "Content-Type: image/png\r\n" +
            lengthHeaders +
            "Connection: close\r\n\r\n");

        Assert.StartsWith($"HTTP/1.1 {expectedStatus}", response, StringComparison.Ordinal);
    }

    [Fact]
    public async Task RejectsChunkedTransferEncoding()
    {
        var response = await SendAndReadToEndAsync(
            $"POST /api/v1/upload/{PairId} HTTP/1.1\r\n" +
            "Host: 127.0.0.1\r\n" +
            $"Authorization: Bearer {Token}\r\n" +
            "Content-Type: image/png\r\n" +
            "Transfer-Encoding: chunked\r\n" +
            "Connection: close\r\n\r\n" +
            "0\r\n\r\n");

        Assert.StartsWith("HTTP/1.1 501", response, StringComparison.Ordinal);
    }

    [Fact]
    public async Task RejectsUnsupportedExpectationBeforeReadingBody()
    {
        var response = await SendAndReadHeaderAsync(
            $"POST /api/v1/upload/{PairId} HTTP/1.1\r\n" +
            "Host: 127.0.0.1\r\n" +
            $"Authorization: Bearer {Token}\r\n" +
            "Content-Type: image/png\r\n" +
            $"Content-Length: {TestPng.OneByOne.Length}\r\n" +
            "Expect: something-else\r\n" +
            "Connection: close\r\n\r\n");

        Assert.StartsWith("HTTP/1.1 417", response, StringComparison.Ordinal);
    }

    [Fact]
    public async Task SendsInterimContinueBeforeAcceptingBody()
    {
        using var client = new TcpClient();
        await client.ConnectAsync(IPAddress.Loopback, Server.BoundPort);
        await using var stream = client.GetStream();
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        var headers = Encoding.ASCII.GetBytes(
            $"POST /api/v1/upload/{PairId} HTTP/1.1\r\n" +
            "Host: 127.0.0.1\r\n" +
            $"Authorization: Bearer {Token}\r\n" +
            "Content-Type: image/png\r\n" +
            $"Content-Length: {TestPng.OneByOne.Length}\r\n" +
            "Expect: 100-continue\r\n" +
            "Connection: close\r\n\r\n");
        await stream.WriteAsync(headers, timeout.Token);

        var interim = await ReadHeaderBlockAsync(stream, timeout.Token);
        Assert.StartsWith("HTTP/1.1 100 Continue", interim, StringComparison.Ordinal);

        await stream.WriteAsync(TestPng.OneByOne, timeout.Token);
        var final = await ReadToEndAsync(stream, timeout.Token);
        Assert.StartsWith("HTTP/1.1 200 OK", final, StringComparison.Ordinal);
    }

    private ReceiverServer Server => _server ?? throw new InvalidOperationException("Test server not initialized.");

    private async Task<string> SendAndReadToEndAsync(string request)
    {
        using var client = new TcpClient();
        await client.ConnectAsync(IPAddress.Loopback, Server.BoundPort);
        await using var stream = client.GetStream();
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        await stream.WriteAsync(Encoding.ASCII.GetBytes(request), timeout.Token);
        return await ReadToEndAsync(stream, timeout.Token);
    }

    private async Task<string> SendAndReadHeaderAsync(string request)
    {
        using var client = new TcpClient();
        await client.ConnectAsync(IPAddress.Loopback, Server.BoundPort);
        await using var stream = client.GetStream();
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        await stream.WriteAsync(Encoding.ASCII.GetBytes(request), timeout.Token);
        return await ReadHeaderBlockAsync(stream, timeout.Token);
    }

    private static async Task<string> ReadHeaderBlockAsync(NetworkStream stream, CancellationToken cancellationToken)
    {
        var bytes = new List<byte>();
        var buffer = new byte[1];
        while (!EndsWithHeaderTerminator(bytes))
        {
            var count = await stream.ReadAsync(buffer, cancellationToken);
            if (count == 0)
            {
                throw new IOException("Connection closed before a complete HTTP header block arrived.");
            }
            bytes.Add(buffer[0]);
            if (bytes.Count > 64 * 1024)
            {
                throw new IOException("HTTP header block exceeded the test safety limit.");
            }
        }
        return Encoding.ASCII.GetString([.. bytes]);
    }

    private static bool EndsWithHeaderTerminator(List<byte> bytes)
    {
        return bytes.Count >= 4 &&
               bytes[^4] == (byte)'\r' &&
               bytes[^3] == (byte)'\n' &&
               bytes[^2] == (byte)'\r' &&
               bytes[^1] == (byte)'\n';
    }

    private static async Task<string> ReadToEndAsync(NetworkStream stream, CancellationToken cancellationToken)
    {
        using var output = new MemoryStream();
        await stream.CopyToAsync(output, cancellationToken);
        return Encoding.ASCII.GetString(output.ToArray());
    }
}
