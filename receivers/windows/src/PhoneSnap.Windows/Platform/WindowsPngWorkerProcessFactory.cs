using System.ComponentModel;
using System.Diagnostics;
using PhoneSnap.Core.Images;

namespace PhoneSnap.Windows.Platform;

internal sealed class WindowsPngWorkerProcessFactory : IPngNormalizationWorkerProcessFactory
{
    private readonly string _executablePath;
    private readonly string? _managedEntryPoint;

    public WindowsPngWorkerProcessFactory()
    {
        _executablePath = Environment.ProcessPath ??
            throw new InvalidOperationException("The PhoneSnap executable path is unavailable.");
        if (Path.GetFileNameWithoutExtension(_executablePath).Equals("dotnet", StringComparison.OrdinalIgnoreCase))
        {
            var commandLine = Environment.GetCommandLineArgs();
            if (commandLine.Length == 0 || !commandLine[0].EndsWith(".dll", StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException("The PhoneSnap managed entry point is unavailable.");
            }

            _managedEntryPoint = Path.GetFullPath(commandLine[0]);
        }
    }

    public IPngNormalizationWorkerProcess Start()
    {
        var startInfo = new ProcessStartInfo(_executablePath)
        {
            CreateNoWindow = true,
            RedirectStandardError = true,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            UseShellExecute = false,
        };
        if (_managedEntryPoint is not null)
        {
            startInfo.ArgumentList.Add(_managedEntryPoint);
        }

        startInfo.ArgumentList.Add(PngNormalizationWorkerProtocol.WorkerArgument);
        try
        {
            var process = Process.Start(startInfo) ??
                throw new IOException("The PNG normalization worker did not start.");
            return new WindowsPngWorkerProcess(process);
        }
        catch (Win32Exception exception)
        {
            throw new IOException("The PNG normalization worker could not start.", exception);
        }
    }

    private sealed class WindowsPngWorkerProcess : IPngNormalizationWorkerProcess
    {
        private readonly Process _process;

        public WindowsPngWorkerProcess(Process process)
        {
            _process = process;
        }

        public Stream StandardInput => _process.StandardInput.BaseStream;

        public Stream StandardOutput => _process.StandardOutput.BaseStream;

        public Stream StandardError => _process.StandardError.BaseStream;

        public int ExitCode => _process.ExitCode;

        public Task WaitForExitAsync()
        {
            return _process.WaitForExitAsync();
        }

        public void Terminate()
        {
            try
            {
                if (!_process.HasExited)
                {
                    _process.Kill(entireProcessTree: true);
                }
            }
            catch (Exception exception) when (exception is Win32Exception or
                                                        InvalidOperationException or
                                                        NotSupportedException or
                                                        AggregateException)
            {
                // The process either exited concurrently or Windows rejected termination.
                // The caller bounds how long it waits for the process and closes all pipes.
            }
        }

        public void Dispose()
        {
            _process.Dispose();
        }
    }
}
