using PhoneSnap.Core.Images;

namespace PhoneSnap.Core.Tests;

public sealed class WorkerProcessPngNormalizerTests
{
    [Fact]
    public async Task SuccessfulWorkerReceivesInputAndReturnsValidatedOutput()
    {
        var process = new FakePngWorkerProcess(
            output: TestPng.OneByOne,
            startsExited: true);
        var normalizer = new WorkerProcessPngNormalizer(
            new FakePngWorkerProcessFactory(process));

        var normalized = await normalizer.NormalizePngAsync(
            TestPng.OneByOne,
            CancellationToken.None);

        Assert.Equal(TestPng.OneByOne, process.ReceivedInput);
        Assert.Equal(TestPng.OneByOne, normalized);
        Assert.Equal(0, process.TerminateCount);
    }

    [Fact]
    public async Task CancellationTerminatesAndReapsRunningWorker()
    {
        var process = new FakePngWorkerProcess();
        var factory = new FakePngWorkerProcessFactory(process);
        var normalizer = new WorkerProcessPngNormalizer(factory);
        using var cancellation = new CancellationTokenSource();

        var normalization = normalizer.NormalizePngAsync(TestPng.OneByOne, cancellation.Token);
        await factory.Started.Task.WaitAsync(TimeSpan.FromSeconds(2));
        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => normalization);
        Assert.True(process.HasExited);
        Assert.True(process.TerminateCount >= 1);
    }

    [Fact]
    public async Task OutputLimitTerminatesWorkerWithoutAcceptingPartialData()
    {
        var process = new FakePngWorkerProcess(output: TestPng.OneByOne);
        var normalizer = new WorkerProcessPngNormalizer(
            new FakePngWorkerProcessFactory(process),
            maximumOutputBytes: TestPng.OneByOne.Length - 1);

        var exception = await Assert.ThrowsAsync<IOException>(() =>
            normalizer.NormalizePngAsync(TestPng.OneByOne, CancellationToken.None));

        Assert.Contains("output limit", exception.Message, StringComparison.Ordinal);
        Assert.True(process.HasExited);
        Assert.True(process.TerminateCount >= 1);
    }

    [Fact]
    public async Task InvalidImageExitIsReportedAsValidationFailure()
    {
        var process = new FakePngWorkerProcess(
            exitCode: PngNormalizationWorkerProtocol.InvalidImageExitCode,
            startsExited: true);
        var normalizer = new WorkerProcessPngNormalizer(
            new FakePngWorkerProcessFactory(process));

        await Assert.ThrowsAsync<PngValidationException>(() =>
            normalizer.NormalizePngAsync(TestPng.OneByOne, CancellationToken.None));
    }
}
