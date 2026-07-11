using System.Net;
using System.Net.Http.Headers;
using PhoneSnap.Core.Delivery;
using PhoneSnap.Core.Images;
using PhoneSnap.Core.Pairing;
using PhoneSnap.Core.Receiver;

namespace PhoneSnap.Core.Tests;

public sealed class ReceiverServerTests : IAsyncLifetime, IDisposable
{
    private const string PairId = "AbCdEf0123-_";
    private const string Token = "0123456789abcdefghijklmnopqrstuvwxyzABCDE_g";
    private readonly TemporaryDirectory _temporary = new();
    private ReceiverServer? _server;
    private HttpClient? _client;

    public async Task InitializeAsync()
    {
        var store = new ImageStore(_temporary.Path, new ValidatingNormalizer());
        _server = new ReceiverServer(
            new ReceiverOptions
            {
                ListenAddress = IPAddress.Loopback,
                Port = 0,
                AdvertisedHost = "127.0.0.1",
            },
            new PairingCredentials(PairId, Token),
            store);
        await _server.StartAsync();
        _client = new HttpClient { BaseAddress = _server.BaseUri };
    }

    public async Task DisposeAsync()
    {
        if (_server is not null)
        {
            await _server.DisposeAsync();
        }

        Dispose();
    }

    public void Dispose()
    {
        _client?.Dispose();
        _temporary.Dispose();
    }

    [Fact]
    public async Task SetupPageProvidesAuthenticatedSafariBatchUploader()
    {
        var response = await Client.GetAsync($"pair/{PairId}");
        var html = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("type=\"file\" multiple accept=\"image/*\"", html, StringComparison.Ordinal);
        Assert.Contains("new FormData()", html, StringComparison.Ordinal);
        Assert.Contains(Token, html, StringComparison.Ordinal);
        Assert.Equal("no-store", response.Headers.CacheControl?.ToString());
        Assert.Contains("script-src 'nonce-", Header(response, "Content-Security-Policy"), StringComparison.Ordinal);
        Assert.Contains("connect-src 'self'", Header(response, "Content-Security-Policy"), StringComparison.Ordinal);
    }

    [Fact]
    public async Task AcceptsAuthorizedRawPngAndRaisesDelivery()
    {
        var delivered = new TaskCompletionSource<UploadDeliveredEventArgs>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        Server.UploadDelivered += (_, eventArgs) => delivered.TrySetResult(eventArgs);
        using var request = AuthorizedPost();
        request.Content = new ByteArrayContent(TestPng.OneByOne);
        request.Content.Headers.ContentType = new MediaTypeHeaderValue("image/png");

        var response = await Client.SendAsync(request);
        var json = await response.Content.ReadAsStringAsync();
        var eventArgs = await delivered.Task.WaitAsync(TimeSpan.FromSeconds(5));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal($"{{\"ok\":true,\"bytes\":{TestPng.OneByOne.Length}}}", json);
        Assert.True(File.Exists(eventArgs.Image.FilePath));
        Assert.Equal(TestPng.OneByOne.Length, eventArgs.AcceptedByteCount);
    }

    [Fact]
    public async Task AcceptsAuthorizedMultipartPng()
    {
        using var request = AuthorizedPost();
        using var multipart = new MultipartFormDataContent("phonesnap-test-boundary");
        var file = new ByteArrayContent(TestPng.OneByOne);
        file.Headers.ContentType = new MediaTypeHeaderValue("image/png");
        multipart.Add(file, "file", "sender-name-is-ignored.png");
        request.Content = multipart;

        var response = await Client.SendAsync(request);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Single(Directory.GetFiles(_temporary.Path, "*.png"));
        Assert.DoesNotContain("sender-name", Path.GetFileName(Directory.GetFiles(_temporary.Path, "*.png")[0]), StringComparison.Ordinal);
    }

    [Fact]
    public async Task RejectsMissingCredentialBeforeImageValidation()
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, $"api/v1/upload/{PairId}");
        request.Content = new ByteArrayContent("not an image"u8.ToArray());
        request.Content.Headers.ContentType = new MediaTypeHeaderValue("image/png");

        var response = await Client.SendAsync(request);

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Equal("Bearer", string.Join(",", response.Headers.WwwAuthenticate));
        Assert.Empty(Directory.GetFiles(_temporary.Path));
    }

    [Fact]
    public async Task RejectsQueryTokenWithoutAuthorizationHeader()
    {
        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            $"api/v1/upload/{PairId}?token={Token}");
        request.Content = new ByteArrayContent(TestPng.OneByOne);
        request.Content.Headers.ContentType = new MediaTypeHeaderValue("image/png");

        var response = await Client.SendAsync(request);

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task RejectsInvalidImageAndWrongMediaType()
    {
        using var invalid = AuthorizedPost();
        invalid.Content = new ByteArrayContent(TestPng.OneByOne[..40]);
        invalid.Content.Headers.ContentType = new MediaTypeHeaderValue("image/png");
        using var wrongType = AuthorizedPost();
        wrongType.Content = new ByteArrayContent(TestPng.OneByOne);
        wrongType.Content.Headers.ContentType = new MediaTypeHeaderValue("image/jpeg");

        var invalidResponse = await Client.SendAsync(invalid);
        var wrongTypeResponse = await Client.SendAsync(wrongType);

        Assert.Equal(HttpStatusCode.UnsupportedMediaType, invalidResponse.StatusCode);
        Assert.Equal(HttpStatusCode.UnsupportedMediaType, wrongTypeResponse.StatusCode);
    }

    [Fact]
    public async Task RejectsEmptyUpload()
    {
        using var request = AuthorizedPost();
        request.Content = new ByteArrayContent([]);
        request.Content.Headers.ContentType = new MediaTypeHeaderValue("image/png");

        var response = await Client.SendAsync(request);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Empty(Directory.GetFiles(_temporary.Path));
    }

    [Fact]
    public async Task UnknownPairIsNotFoundAndWrongMethodIsRejected()
    {
        var unknown = await Client.PostAsync("api/v1/upload/wrong-pair", new ByteArrayContent(TestPng.OneByOne));
        var wrongMethod = await Client.GetAsync($"api/v1/upload/{PairId}");

        Assert.Equal(HttpStatusCode.NotFound, unknown.StatusCode);
        Assert.Equal(HttpStatusCode.MethodNotAllowed, wrongMethod.StatusCode);
        Assert.Contains("POST", wrongMethod.Content.Headers.Allow);
    }

    private ReceiverServer Server => _server ?? throw new InvalidOperationException("Test server not initialized.");

    private HttpClient Client => _client ?? throw new InvalidOperationException("Test client not initialized.");

    private static HttpRequestMessage AuthorizedPost()
    {
        var request = new HttpRequestMessage(HttpMethod.Post, $"api/v1/upload/{PairId}");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", Token);
        return request;
    }

    private static string Header(HttpResponseMessage response, string name)
    {
        return string.Join(",", response.Headers.GetValues(name));
    }
}
