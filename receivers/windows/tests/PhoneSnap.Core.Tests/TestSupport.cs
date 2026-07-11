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
    public int CallCount { get; private set; }

    public byte[] NormalizePng(ReadOnlyMemory<byte> encodedImage)
    {
        CallCount++;
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
