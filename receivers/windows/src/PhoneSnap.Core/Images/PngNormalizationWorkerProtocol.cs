namespace PhoneSnap.Core.Images;

public static class PngNormalizationWorkerProtocol
{
    public const string WorkerArgument = "--phonesnap-png-worker";
    public const int SuccessExitCode = 0;
    public const int InvalidImageExitCode = 2;
    public const int FailureExitCode = 3;
    public const int MaximumInputBytes = 32 * 1024 * 1024;
    public const int MaximumOutputBytes = 256 * 1024 * 1024;
    public const int MaximumDiagnosticBytes = 4 * 1024;
}
