using System.Net;
using System.Net.Http.Headers;
using PhoneSnap.Core.Images;
using PhoneSnap.Core.Pairing;
using PhoneSnap.Core.Receiver;

namespace PhoneSnap.Core.Tests;

public sealed class ReceiverWorkerLifecycleTests
{
    private const string PairId = "AbCdEf0123-_";
    private const string Token = "0123456789abcdefghijklmnopqrstuvwxyzABCDE_g";

    [Fact]
    public async Task RequestDeadlineTerminatesDecodeWorkerBeforeReturningTimeout()
    {
        using var temporary = new TemporaryDirectory();
        var process = new FakePngWorkerProcess();
        var factory = new FakePngWorkerProcessFactory(process);
        var normalizer = new WorkerProcessPngNormalizer(factory);
        await using var receiver = CreateReceiver(
            temporary.Path,
            normalizer,
            TimeSpan.FromMilliseconds(150));
        await receiver.StartAsync();
        using var client = new HttpClient { BaseAddress = receiver.BaseUri };
        using var request = AuthorizedPngPost();

        using var response = await client.SendAsync(request);

        Assert.Equal(HttpStatusCode.RequestTimeout, response.StatusCode);
        Assert.True(process.HasExited);
        Assert.True(process.TerminateCount >= 1);
        Assert.Empty(Directory.GetFiles(temporary.Path, "*.png"));
    }

    [Fact]
    public async Task ReceiverStopTerminatesDecodeWorkerAndCompletesShutdown()
    {
        using var temporary = new TemporaryDirectory();
        var process = new FakePngWorkerProcess();
        var factory = new FakePngWorkerProcessFactory(process);
        var normalizer = new WorkerProcessPngNormalizer(factory);
        await using var receiver = CreateReceiver(
            temporary.Path,
            normalizer,
            TimeSpan.FromSeconds(30));
        await receiver.StartAsync();
        using var client = new HttpClient { BaseAddress = receiver.BaseUri };
        using var request = AuthorizedPngPost();
        var upload = client.SendAsync(request);
        await factory.Started.Task.WaitAsync(TimeSpan.FromSeconds(2));

        await receiver.StopAsync().WaitAsync(TimeSpan.FromSeconds(5));

        Assert.Equal(ReceiverActivity.Stopped, receiver.State.Activity);
        Assert.True(process.HasExited);
        Assert.True(process.TerminateCount >= 1);
        await ObserveStoppedUploadAsync(upload);
    }

    private static ReceiverServer CreateReceiver(
        string folder,
        IImageNormalizer normalizer,
        TimeSpan requestTimeout)
    {
        return new ReceiverServer(
            new ReceiverOptions
            {
                ListenAddress = IPAddress.Loopback,
                Port = 0,
                AdvertisedHost = "127.0.0.1",
                RequestTimeout = requestTimeout,
            },
            new PairingCredentials(PairId, Token),
            new ImageStore(folder, normalizer));
    }

    private static HttpRequestMessage AuthorizedPngPost()
    {
        var request = new HttpRequestMessage(HttpMethod.Post, $"api/v1/upload/{PairId}");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", Token);
        request.Content = new ByteArrayContent(TestPng.OneByOne);
        request.Content.Headers.ContentType = new MediaTypeHeaderValue("image/png");
        return request;
    }

    private static async Task ObserveStoppedUploadAsync(Task<HttpResponseMessage> upload)
    {
        try
        {
            using var response = await upload.WaitAsync(TimeSpan.FromSeconds(2));
        }
        catch (Exception exception) when (exception is HttpRequestException or
                                                    OperationCanceledException or
                                                    TimeoutException)
        {
            // Stopping the listener may close the in-flight response transport.
        }
    }
}
