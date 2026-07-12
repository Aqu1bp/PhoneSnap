using PhoneSnap.Core.Images;

namespace PhoneSnap.Windows.Platform;

internal static class WindowsPngWorker
{
    public static int Run(Stream input, Stream output)
    {
        try
        {
            var encodedImage = ReadBounded(input, PngNormalizationWorkerProtocol.MaximumInputBytes);
            var normalized = new WindowsPngNormalizer().NormalizePng(encodedImage);
            if (normalized.Length > PngNormalizationWorkerProtocol.MaximumOutputBytes)
            {
                return PngNormalizationWorkerProtocol.FailureExitCode;
            }

            output.Write(normalized);
            output.Flush();
            return PngNormalizationWorkerProtocol.SuccessExitCode;
        }
        catch (PngValidationException)
        {
            return PngNormalizationWorkerProtocol.InvalidImageExitCode;
        }
        catch
        {
            return PngNormalizationWorkerProtocol.FailureExitCode;
        }
    }

    private static byte[] ReadBounded(Stream input, int maximumBytes)
    {
        using var encodedImage = new MemoryStream(Math.Min(maximumBytes, 64 * 1024));
        var buffer = new byte[64 * 1024];
        while (true)
        {
            var bytesRead = input.Read(buffer, 0, buffer.Length);
            if (bytesRead == 0)
            {
                return encodedImage.ToArray();
            }

            if (encodedImage.Length + bytesRead > maximumBytes)
            {
                throw new PngValidationException("The PNG exceeds the worker input limit.");
            }

            encodedImage.Write(buffer, 0, bytesRead);
        }
    }
}
