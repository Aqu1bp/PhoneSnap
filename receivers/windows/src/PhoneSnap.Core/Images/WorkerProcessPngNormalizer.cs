namespace PhoneSnap.Core.Images;

public interface IPngNormalizationWorkerProcessFactory
{
    IPngNormalizationWorkerProcess Start();
}

public interface IPngNormalizationWorkerProcess : IDisposable
{
    Stream StandardInput { get; }

    Stream StandardOutput { get; }

    Stream StandardError { get; }

    int ExitCode { get; }

    Task WaitForExitAsync();

    void Terminate();
}

public sealed class WorkerProcessPngNormalizer : IImageNormalizer
{
    private static readonly TimeSpan TerminationGracePeriod = TimeSpan.FromSeconds(1);

    private readonly IPngNormalizationWorkerProcessFactory _processFactory;
    private readonly long _maximumPixelCount;
    private readonly int _maximumInputBytes;
    private readonly int _maximumOutputBytes;

    public WorkerProcessPngNormalizer(
        IPngNormalizationWorkerProcessFactory processFactory,
        long maximumPixelCount = PngValidator.DefaultMaximumPixelCount,
        int maximumInputBytes = PngNormalizationWorkerProtocol.MaximumInputBytes,
        int maximumOutputBytes = PngNormalizationWorkerProtocol.MaximumOutputBytes)
    {
        _processFactory = processFactory ?? throw new ArgumentNullException(nameof(processFactory));
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maximumPixelCount);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maximumInputBytes);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maximumOutputBytes);
        _maximumPixelCount = maximumPixelCount;
        _maximumInputBytes = maximumInputBytes;
        _maximumOutputBytes = maximumOutputBytes;
    }

    public async Task<byte[]> NormalizePngAsync(
        ReadOnlyMemory<byte> encodedImage,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (encodedImage.IsEmpty || encodedImage.Length > _maximumInputBytes)
        {
            throw new PngValidationException("The PNG exceeds the worker input limit.");
        }

        _ = PngValidator.ValidateHeader(encodedImage.Span, _maximumPixelCount);
        using var process = _processFactory.Start();
        using var cancellationRegistration = cancellationToken.UnsafeRegister(
            static state => ((IPngNormalizationWorkerProcess)state!).Terminate(),
            process);

        var inputTask = WriteInputAsync(process.StandardInput, encodedImage);
        var outputTask = ReadBoundedAsync(
            process.StandardOutput,
            _maximumOutputBytes,
            "The PNG normalization worker exceeded its output limit.");
        var errorTask = ReadBoundedAsync(
            process.StandardError,
            PngNormalizationWorkerProtocol.MaximumDiagnosticBytes,
            "The PNG normalization worker exceeded its diagnostic limit.");
        var exitTask = process.WaitForExitAsync();
        var completion = Task.WhenAll(
            exitTask,
            TerminateOnFailureAsync(inputTask, process),
            TerminateOnFailureAsync(outputTask, process),
            TerminateOnFailureAsync(errorTask, process));

        try
        {
            await completion.WaitAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (Exception) when (cancellationToken.IsCancellationRequested)
        {
            process.Terminate();
            await ObserveTerminationAsync(completion).ConfigureAwait(false);
            throw new OperationCanceledException(cancellationToken);
        }
        catch
        {
            process.Terminate();
            await ObserveTerminationAsync(completion).ConfigureAwait(false);
            throw;
        }

        cancellationToken.ThrowIfCancellationRequested();
        _ = await errorTask.ConfigureAwait(false);
        var output = await outputTask.ConfigureAwait(false);
        switch (process.ExitCode)
        {
            case PngNormalizationWorkerProtocol.SuccessExitCode:
                break;
            case PngNormalizationWorkerProtocol.InvalidImageExitCode:
                throw new PngValidationException("The PNG could not be decoded.");
            default:
                throw new IOException("The PNG normalization worker failed.");
        }

        if (output.Length == 0)
        {
            throw new IOException("The PNG normalization worker returned no image data.");
        }

        try
        {
            _ = PngValidator.ValidateHeader(output, _maximumPixelCount);
        }
        catch (PngValidationException exception)
        {
            throw new IOException("The PNG normalization worker returned invalid image data.", exception);
        }

        return output;
    }

    private static async Task WriteInputAsync(Stream stream, ReadOnlyMemory<byte> encodedImage)
    {
        try
        {
            await stream.WriteAsync(encodedImage, CancellationToken.None).ConfigureAwait(false);
            await stream.FlushAsync(CancellationToken.None).ConfigureAwait(false);
        }
        finally
        {
            stream.Dispose();
        }
    }

    private static async Task<byte[]> ReadBoundedAsync(Stream stream, int maximumBytes, string limitMessage)
    {
        using var output = new MemoryStream(Math.Min(maximumBytes, 64 * 1024));
        var buffer = new byte[64 * 1024];
        while (true)
        {
            var bytesRead = await stream.ReadAsync(buffer, CancellationToken.None).ConfigureAwait(false);
            if (bytesRead == 0)
            {
                return output.ToArray();
            }

            if (output.Length + bytesRead > maximumBytes)
            {
                throw new IOException(limitMessage);
            }

            output.Write(buffer, 0, bytesRead);
        }
    }

    private static async Task TerminateOnFailureAsync(
        Task task,
        IPngNormalizationWorkerProcess process)
    {
        try
        {
            await task.ConfigureAwait(false);
        }
        catch
        {
            process.Terminate();
            throw;
        }
    }

    private static async Task ObserveTerminationAsync(Task completion)
    {
        try
        {
            await completion.WaitAsync(TerminationGracePeriod).ConfigureAwait(false);
        }
        catch
        {
            if (!completion.IsCompleted)
            {
                _ = completion.ContinueWith(
                    static task => _ = task.Exception,
                    CancellationToken.None,
                    TaskContinuationOptions.OnlyOnFaulted | TaskContinuationOptions.ExecuteSynchronously,
                    TaskScheduler.Default);
            }
        }
    }
}
