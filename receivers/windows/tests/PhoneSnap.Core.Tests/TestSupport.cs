using PhoneSnap.Core.Images;
using PhoneSnap.Core.Pairing;

namespace PhoneSnap.Core.Tests;

internal static class TestPng
{
    public static byte[] OneByOne { get; } = Convert.FromBase64String(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==");
}

internal sealed class ValidatingNormalizer : IImageNormalizer
{
    private readonly int _releaseAfterCalls;
    private readonly TaskCompletionSource<bool>? _concurrentCallsArrived;
    private int _callCount;

    public ValidatingNormalizer(int releaseAfterCalls = 1)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(releaseAfterCalls);
        _releaseAfterCalls = releaseAfterCalls;
        if (releaseAfterCalls > 1)
        {
            _concurrentCallsArrived = new TaskCompletionSource<bool>(
                TaskCreationOptions.RunContinuationsAsynchronously);
        }
    }

    public int CallCount => Volatile.Read(ref _callCount);

    public async Task<byte[]> NormalizePngAsync(
        ReadOnlyMemory<byte> encodedImage,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var callCount = Interlocked.Increment(ref _callCount);
        if (_concurrentCallsArrived is not null)
        {
            if (callCount == _releaseAfterCalls)
            {
                _concurrentCallsArrived.TrySetResult(true);
            }

            await _concurrentCallsArrived.Task.WaitAsync(cancellationToken);
        }
        else
        {
            await Task.Yield();
        }

        cancellationToken.ThrowIfCancellationRequested();
        _ = PngValidator.ValidateHeader(encodedImage.Span);
        if (!encodedImage.Span.SequenceEqual(TestPng.OneByOne))
        {
            throw new PngValidationException("The fake decoder rejected corrupt PNG data.");
        }

        return encodedImage.ToArray();
    }
}

internal sealed class TestSecretProtector : ISecretProtector
{
    public byte[] Protect(ReadOnlySpan<byte> plaintext)
    {
        return plaintext.ToArray().Select(value => (byte)(value ^ 0xa5)).ToArray();
    }

    public byte[] Unprotect(ReadOnlySpan<byte> protectedData)
    {
        return Protect(protectedData);
    }
}

internal sealed class BlockingImageStore : IImageStore
{
    public TaskCompletionSource<bool> Started { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);

    public async Task<SavedImage> SaveAsync(ReadOnlyMemory<byte> encodedImage, CancellationToken cancellationToken)
    {
        Started.TrySetResult(true);
        await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
        throw new InvalidOperationException("The cancellation-aware test store unexpectedly completed.");
    }
}

internal sealed class FakePngWorkerProcessFactory : IPngNormalizationWorkerProcessFactory
{
    private readonly FakePngWorkerProcess _process;
    private int _startCount;

    public FakePngWorkerProcessFactory(FakePngWorkerProcess process)
    {
        _process = process;
    }

    public TaskCompletionSource<bool> Started { get; } =
        new(TaskCreationOptions.RunContinuationsAsynchronously);

    public IPngNormalizationWorkerProcess Start()
    {
        Assert.Equal(1, Interlocked.Increment(ref _startCount));
        Started.TrySetResult(true);
        return _process;
    }
}

internal sealed class FakePngWorkerProcess : IPngNormalizationWorkerProcess
{
    private readonly MemoryStream _standardInput = new();
    private readonly MemoryStream _standardOutput;
    private readonly MemoryStream _standardError;
    private readonly TaskCompletionSource<bool> _exited =
        new(TaskCreationOptions.RunContinuationsAsynchronously);
    private int _exitCode;
    private int _terminateCount;

    public FakePngWorkerProcess(
        ReadOnlyMemory<byte> output = default,
        ReadOnlyMemory<byte> error = default,
        int exitCode = PngNormalizationWorkerProtocol.SuccessExitCode,
        bool startsExited = false)
    {
        _standardOutput = new MemoryStream(output.ToArray(), writable: false);
        _standardError = new MemoryStream(error.ToArray(), writable: false);
        _exitCode = exitCode;
        if (startsExited)
        {
            _exited.TrySetResult(true);
        }
    }

    public Stream StandardInput => _standardInput;

    public Stream StandardOutput => _standardOutput;

    public Stream StandardError => _standardError;

    public int ExitCode => _exitCode;

    public int TerminateCount => Volatile.Read(ref _terminateCount);

    public bool HasExited => _exited.Task.IsCompletedSuccessfully;

    public byte[] ReceivedInput => _standardInput.ToArray();

    public Task WaitForExitAsync()
    {
        return _exited.Task;
    }

    public void Terminate()
    {
        Interlocked.Increment(ref _terminateCount);
        _exitCode = -1;
        _exited.TrySetResult(true);
    }

    public void Dispose()
    {
        _standardInput.Dispose();
        _standardOutput.Dispose();
        _standardError.Dispose();
    }
}

internal sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
{
    public override TimeZoneInfo LocalTimeZone => TimeZoneInfo.Utc;

    public override DateTimeOffset GetUtcNow() => now;
}

internal sealed class TemporaryDirectory : IDisposable
{
    public TemporaryDirectory()
    {
        Path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"phonesnap-tests-{Guid.NewGuid():N}");
        Directory.CreateDirectory(Path);
    }

    public string Path { get; }

    public void Dispose()
    {
        try
        {
            Directory.Delete(Path, recursive: true);
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }
}
