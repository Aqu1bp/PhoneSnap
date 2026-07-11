using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Server.Kestrel.Core;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Net.Http.Headers;
using PhoneSnap.Core.Delivery;
using PhoneSnap.Core.Images;
using PhoneSnap.Core.Pairing;

namespace PhoneSnap.Core.Receiver;

public sealed class ReceiverServer : IAsyncDisposable
{
    private readonly ReceiverOptions _options;
    private readonly PairingCredentials _pairing;
    private readonly IImageStore _imageStore;
    private readonly SemaphoreSlim _processingGate = new(1, 1);
    private readonly SemaphoreSlim _lifecycleGate = new(1, 1);
    private readonly object _addressGate = new();
    private WebApplication? _application;
    private string? _advertisedHost;
    private Uri? _baseUri;
    private int _boundPort;
    private bool _disposed;

    public ReceiverServer(ReceiverOptions options, PairingCredentials pairing, IImageStore imageStore)
    {
        _options = options ?? throw new ArgumentNullException(nameof(options));
        _options.Validate();
        _pairing = pairing ?? throw new ArgumentNullException(nameof(pairing));
        _imageStore = imageStore ?? throw new ArgumentNullException(nameof(imageStore));
        _advertisedHost = options.AdvertisedHost;
        if (_advertisedHost is not null)
        {
            _ = BuildBaseUri(_advertisedHost, 1);
        }
    }

    public event EventHandler<UploadDeliveredEventArgs>? UploadDelivered;

    public event EventHandler<ReceiverStateChangedEventArgs>? StateChanged;

    public ReceiverState State { get; private set; } = ReceiverState.Stopped;

    public int BoundPort
    {
        get
        {
            lock (_addressGate)
            {
                return _boundPort;
            }
        }
    }

    public Uri? BaseUri
    {
        get
        {
            lock (_addressGate)
            {
                return _baseUri;
            }
        }
    }

    public Uri? SetupUri
    {
        get
        {
            var baseUri = BaseUri;
            return baseUri is null ? null : new Uri(baseUri, $"pair/{_pairing.PairId}");
        }
    }

    public Uri? UploadUri
    {
        get
        {
            var baseUri = BaseUri;
            return baseUri is null ? null : new Uri(baseUri, $"api/v1/upload/{_pairing.PairId}");
        }
    }

    public async Task StartAsync(CancellationToken cancellationToken = default)
    {
        await _lifecycleGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            await StartCoreAsync(cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            _lifecycleGate.Release();
        }
    }

    public async Task StopAsync(CancellationToken cancellationToken = default)
    {
        await _lifecycleGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            await StopCoreAsync(cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            _lifecycleGate.Release();
        }
    }

    public void UpdateAdvertisedHost(string? advertisedHost)
    {
        if (advertisedHost is not null)
        {
            ArgumentException.ThrowIfNullOrWhiteSpace(advertisedHost);
            _ = BuildBaseUri(advertisedHost, 1);
        }

        lock (_addressGate)
        {
            _advertisedHost = advertisedHost;
            _baseUri = advertisedHost is null || _boundPort == 0
                ? null
                : BuildBaseUri(advertisedHost, _boundPort);
        }
    }

    public async ValueTask DisposeAsync()
    {
        await _lifecycleGate.WaitAsync().ConfigureAwait(false);
        try
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;
            await StopCoreAsync(CancellationToken.None).ConfigureAwait(false);
        }
        finally
        {
            _lifecycleGate.Release();
        }

        _processingGate.Dispose();
        GC.SuppressFinalize(this);
    }

    private async Task StartCoreAsync(CancellationToken cancellationToken)
    {
        if (_application is not null)
        {
            throw new InvalidOperationException("The receiver is already running.");
        }

        ChangeState(new ReceiverState(ReceiverActivity.Starting));
        var builder = WebApplication.CreateSlimBuilder(new WebApplicationOptions
        {
            ApplicationName = typeof(ReceiverServer).Assembly.GetName().Name,
            Args = [],
        });
        builder.Logging.ClearProviders();
        builder.WebHost.ConfigureKestrel(kestrel =>
        {
            kestrel.AddServerHeader = false;
            kestrel.Limits.MaxRequestBodySize = _options.MaximumBodyBytes;
            kestrel.Limits.MaxConcurrentConnections = _options.MaximumConcurrentConnections;
            kestrel.Limits.RequestHeadersTimeout = _options.HeaderTimeout;
            kestrel.Limits.KeepAliveTimeout = _options.KeepAliveTimeout;
            kestrel.Listen(_options.ListenAddress, _options.Port, listen =>
            {
                listen.Protocols = HttpProtocols.Http1;
            });
        });
        builder.Services.Configure<FormOptions>(form =>
        {
            form.MultipartBodyLengthLimit = _options.MaximumBodyBytes;
            form.BufferBodyLengthLimit = _options.MaximumBodyBytes;
            form.ValueLengthLimit = _options.MaximumBodyBytes;
            form.MultipartHeadersLengthLimit = 16 * 1024;
            form.MultipartBoundaryLengthLimit = 256;
        });

        var application = builder.Build();
        application.Run(HandleRequestAsync);

        try
        {
            await application.StartAsync(cancellationToken).ConfigureAwait(false);
            SetBoundPort(ResolveBoundPort(application));
            _application = application;
            ChangeState(new ReceiverState(ReceiverActivity.Ready));
        }
        catch (Exception exception)
        {
            SetBoundPort(0);
            ChangeState(new ReceiverState(ReceiverActivity.Failed, exception.Message));
            await application.DisposeAsync().ConfigureAwait(false);
            throw;
        }
    }

    private async Task StopCoreAsync(CancellationToken cancellationToken)
    {
        var application = _application;
        _application = null;
        if (application is null)
        {
            return;
        }

        try
        {
            await application.StopAsync(cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            try
            {
                await application.DisposeAsync().ConfigureAwait(false);
            }
            finally
            {
                SetBoundPort(0);
                ChangeState(ReceiverState.Stopped);
            }
        }
    }

    private async Task HandleRequestAsync(HttpContext context)
    {
        AddCommonResponseHeaders(context.Response);
        var path = context.Request.Path.Value ?? string.Empty;
        var setupPath = $"/pair/{_pairing.PairId}";
        var uploadPath = $"/api/v1/upload/{_pairing.PairId}";

        if (path.Equals(setupPath, StringComparison.Ordinal))
        {
            if (!HttpMethods.IsGet(context.Request.Method))
            {
                context.Response.Headers.Allow = HttpMethods.Get;
                await WriteTextAsync(context, StatusCodes.Status405MethodNotAllowed, "method not allowed").ConfigureAwait(false);
                return;
            }

            var uploadUri = UploadUri;
            if (uploadUri is null)
            {
                await WriteTextAsync(context, StatusCodes.Status503ServiceUnavailable, "receiver has no reachable LAN address").ConfigureAwait(false);
                return;
            }

            var page = SetupPage.Render(uploadUri, _pairing);
            context.Response.Headers["Content-Security-Policy"] = page.ContentSecurityPolicy;
            context.Response.StatusCode = StatusCodes.Status200OK;
            context.Response.ContentType = "text/html; charset=utf-8";
            await context.Response.WriteAsync(page.Html, context.RequestAborted).ConfigureAwait(false);
            return;
        }

        if (path.StartsWith("/pair/", StringComparison.Ordinal) ||
            path.StartsWith("/api/v1/upload/", StringComparison.Ordinal))
        {
            if (!path.Equals(uploadPath, StringComparison.Ordinal))
            {
                await WriteTextAsync(context, StatusCodes.Status404NotFound, "not found").ConfigureAwait(false);
                return;
            }

            await HandleUploadAsync(context).ConfigureAwait(false);
            return;
        }

        await WriteTextAsync(context, StatusCodes.Status404NotFound, "not found").ConfigureAwait(false);
    }

    private async Task HandleUploadAsync(HttpContext context)
    {
        if (!HttpMethods.IsPost(context.Request.Method))
        {
            context.Response.Headers.Allow = HttpMethods.Post;
            await WriteTextAsync(context, StatusCodes.Status405MethodNotAllowed, "method not allowed").ConfigureAwait(false);
            return;
        }

        if (!HasValidAuthorization(context.Request))
        {
            context.Response.Headers.WWWAuthenticate = "Bearer";
            await WriteTextAsync(context, StatusCodes.Status401Unauthorized, "unauthorized").ConfigureAwait(false);
            return;
        }

        if (HasUnsupportedExpectation(context.Request))
        {
            await WriteTextAsync(context, StatusCodes.Status417ExpectationFailed, "unsupported Expect header").ConfigureAwait(false);
            return;
        }

        if (HasUnsupportedTransferEncoding(context.Request))
        {
            await WriteTextAsync(
                context,
                StatusCodes.Status501NotImplemented,
                "Transfer-Encoding is not supported; send a Content-Length body").ConfigureAwait(false);
            return;
        }

        var contentLengthStatus = ValidateContentLength(context.Request, out var contentLength);
        if (contentLengthStatus is not null)
        {
            await WriteTextAsync(context, contentLengthStatus.Value.Status, contentLengthStatus.Value.Message).ConfigureAwait(false);
            return;
        }

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(context.RequestAborted);
        timeout.CancelAfter(_options.RequestTimeout);

        byte[] imageBytes;
        try
        {
            imageBytes = await ExtractImageAsync(context.Request, contentLength, timeout.Token).ConfigureAwait(false);
        }
        catch (UploadFormatException exception)
        {
            await WriteTextAsync(context, exception.StatusCode, exception.Message).ConfigureAwait(false);
            return;
        }
        catch (Microsoft.AspNetCore.Http.BadHttpRequestException exception)
            when (exception.StatusCode == StatusCodes.Status413PayloadTooLarge)
        {
            await WriteTextAsync(context, StatusCodes.Status413PayloadTooLarge, "payload too large").ConfigureAwait(false);
            return;
        }
        catch (InvalidDataException)
        {
            await WriteTextAsync(context, StatusCodes.Status400BadRequest, "malformed request body").ConfigureAwait(false);
            return;
        }
        catch (OperationCanceledException) when (!context.RequestAborted.IsCancellationRequested)
        {
            await WriteTextAsync(context, StatusCodes.Status408RequestTimeout, "request timed out").ConfigureAwait(false);
            return;
        }

        SavedImage savedImage;
        try
        {
            await _processingGate.WaitAsync(timeout.Token).ConfigureAwait(false);
            try
            {
                savedImage = await _imageStore.SaveAsync(imageBytes, timeout.Token).ConfigureAwait(false);
            }
            finally
            {
                _processingGate.Release();
            }
        }
        catch (PngValidationException)
        {
            await WriteTextAsync(context, StatusCodes.Status415UnsupportedMediaType, "body is not a decodable PNG image").ConfigureAwait(false);
            return;
        }
        catch (OperationCanceledException) when (context.RequestAborted.IsCancellationRequested)
        {
            return;
        }
        catch (OperationCanceledException)
        {
            await WriteTextAsync(context, StatusCodes.Status408RequestTimeout, "request timed out").ConfigureAwait(false);
            return;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            await WriteTextAsync(context, StatusCodes.Status500InternalServerError, "could not store image").ConfigureAwait(false);
            return;
        }

        context.Response.StatusCode = StatusCodes.Status200OK;
        context.Response.ContentType = "application/json; charset=utf-8";
        var response = JsonSerializer.Serialize(new UploadResponse(true, imageBytes.Length));
        RaiseUploadDelivered(new UploadDeliveredEventArgs(savedImage, imageBytes.Length));
        try
        {
            await context.Response.WriteAsync(response, context.RequestAborted).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (context.RequestAborted.IsCancellationRequested)
        {
            // The file is already committed and surfaced locally.
        }
        catch (IOException)
        {
            // The response transport failed after a successful local delivery.
        }
    }

    private async Task<byte[]> ExtractImageAsync(HttpRequest request, long contentLength, CancellationToken cancellationToken)
    {
        if (IsMediaType(request.ContentType, "image/png"))
        {
            using var stream = new MemoryStream((int)contentLength);
            await request.Body.CopyToAsync(stream, cancellationToken).ConfigureAwait(false);
            if (stream.Length != contentLength || stream.Length == 0)
            {
                throw new UploadFormatException(StatusCodes.Status400BadRequest, "incomplete or empty request body");
            }

            return stream.ToArray();
        }

        if (request.HasFormContentType && IsMediaType(request.ContentType, "multipart/form-data"))
        {
            var form = await request.ReadFormAsync(cancellationToken).ConfigureAwait(false);
            if (form.Count != 0 || form.Files.Count != 1)
            {
                throw new UploadFormatException(StatusCodes.Status400BadRequest, "multipart body must contain one file part");
            }

            var file = form.Files[0];
            if (!file.Name.Equals("file", StringComparison.Ordinal) || !IsMediaType(file.ContentType, "image/png"))
            {
                throw new UploadFormatException(StatusCodes.Status415UnsupportedMediaType, "multipart file must be an image/png part named file");
            }

            if (file.Length <= 0)
            {
                throw new UploadFormatException(StatusCodes.Status400BadRequest, "empty upload body");
            }

            if (file.Length > _options.MaximumBodyBytes || file.Length > int.MaxValue)
            {
                throw new UploadFormatException(StatusCodes.Status413PayloadTooLarge, "payload too large");
            }

            using var stream = new MemoryStream((int)file.Length);
            await file.CopyToAsync(stream, cancellationToken).ConfigureAwait(false);
            if (stream.Length != file.Length)
            {
                throw new UploadFormatException(StatusCodes.Status400BadRequest, "incomplete multipart file");
            }

            return stream.ToArray();
        }

        throw new UploadFormatException(StatusCodes.Status415UnsupportedMediaType, "Content-Type must be image/png or multipart/form-data");
    }

    private bool HasValidAuthorization(HttpRequest request)
    {
        var values = request.Headers[HeaderNames.Authorization];
        if (values.Count != 1)
        {
            return false;
        }

        var value = values[0];
        if (value is null)
        {
            return false;
        }

        var separator = value.IndexOf(' ');
        if (separator <= 0 || !value[..separator].Equals("Bearer", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var candidate = value[(separator + 1)..];
        if (candidate.Length == 0 || !candidate.Equals(candidate.Trim(), StringComparison.Ordinal))
        {
            return false;
        }

        var expectedDigest = SHA256.HashData(Encoding.UTF8.GetBytes(_pairing.Token));
        var candidateDigest = SHA256.HashData(Encoding.UTF8.GetBytes(candidate));
        return CryptographicOperations.FixedTimeEquals(expectedDigest, candidateDigest);
    }

    private static bool HasUnsupportedExpectation(HttpRequest request)
    {
        var values = request.Headers[HeaderNames.Expect];
        return values.Count > 0 &&
               (values.Count != 1 || !string.Equals(values[0], "100-continue", StringComparison.OrdinalIgnoreCase));
    }

    private static bool HasUnsupportedTransferEncoding(HttpRequest request)
    {
        var values = request.Headers[HeaderNames.TransferEncoding];
        return values.Count > 0 &&
               (values.Count != 1 || !string.Equals(values[0], "identity", StringComparison.OrdinalIgnoreCase));
    }

    private (int Status, string Message)? ValidateContentLength(HttpRequest request, out long contentLength)
    {
        contentLength = 0;
        var values = request.Headers[HeaderNames.ContentLength];
        if (values.Count == 0)
        {
            return (StatusCodes.Status411LengthRequired, "Content-Length is required");
        }

        var raw = values.Count == 1 ? values[0] : null;
        if (raw is null || raw.Contains(',', StringComparison.Ordinal) ||
            !long.TryParse(raw, NumberStyles.None, CultureInfo.InvariantCulture, out contentLength))
        {
            return (StatusCodes.Status400BadRequest, "invalid Content-Length");
        }

        if (contentLength == 0)
        {
            return (StatusCodes.Status400BadRequest, "empty upload body");
        }

        if (contentLength > _options.MaximumBodyBytes)
        {
            return (StatusCodes.Status413PayloadTooLarge, "payload too large");
        }

        return null;
    }

    private static bool IsMediaType(string? value, string expected)
    {
        return MediaTypeHeaderValue.TryParse(value, out var parsed) &&
               string.Equals(parsed.MediaType.Value, expected, StringComparison.OrdinalIgnoreCase);
    }

    private static void AddCommonResponseHeaders(HttpResponse response)
    {
        response.Headers.CacheControl = "no-store";
        response.Headers[HeaderNames.XContentTypeOptions] = "nosniff";
        response.Headers["Referrer-Policy"] = "no-referrer";
        response.Headers["Content-Security-Policy"] = "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'";
    }

    private static async Task WriteTextAsync(HttpContext context, int statusCode, string text)
    {
        if (context.Response.HasStarted)
        {
            context.Abort();
            return;
        }

        context.Response.StatusCode = statusCode;
        context.Response.ContentType = "text/plain; charset=utf-8";
        await context.Response.WriteAsync(text, context.RequestAborted).ConfigureAwait(false);
    }

    private static int ResolveBoundPort(WebApplication application)
    {
        var server = application.Services.GetRequiredService<IServer>();
        var addresses = server.Features.Get<IServerAddressesFeature>()?.Addresses;
        var address = addresses?.FirstOrDefault();
        if (address is null || !Uri.TryCreate(address, UriKind.Absolute, out var uri))
        {
            throw new InvalidOperationException("Kestrel did not report its bound address.");
        }

        return uri.Port;
    }

    private void SetBoundPort(int port)
    {
        lock (_addressGate)
        {
            _boundPort = port;
            _baseUri = port == 0 || _advertisedHost is null
                ? null
                : BuildBaseUri(_advertisedHost, port);
        }
    }

    private static Uri BuildBaseUri(string host, int port)
    {
        var builder = new UriBuilder(Uri.UriSchemeHttp, host, port, "/");
        return builder.Uri;
    }

    private void ChangeState(ReceiverState state)
    {
        State = state;
        StateChanged?.Invoke(this, new ReceiverStateChangedEventArgs(state));
    }

    private void RaiseUploadDelivered(UploadDeliveredEventArgs eventArgs)
    {
        try
        {
            UploadDelivered?.Invoke(this, eventArgs);
        }
        catch
        {
            // Delivery succeeded even if a platform UI subscriber failed.
        }
    }

    private sealed record UploadResponse(
        [property: JsonPropertyName("ok")] bool Ok,
        [property: JsonPropertyName("bytes")] int Bytes);

    private sealed class UploadFormatException : Exception
    {
        public UploadFormatException(int statusCode, string message)
            : base(message)
        {
            StatusCode = statusCode;
        }

        public int StatusCode { get; }
    }
}
