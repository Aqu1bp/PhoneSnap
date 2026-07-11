using System.Buffers.Binary;

namespace PhoneSnap.Core.Images;

public readonly record struct PngInfo(int Width, int Height);

public static class PngValidator
{
    public const long DefaultMaximumPixelCount = 50_000_000;

    private static ReadOnlySpan<byte> Signature => [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

    public static PngInfo ValidateHeader(ReadOnlySpan<byte> data, long maximumPixelCount = DefaultMaximumPixelCount)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maximumPixelCount);

        if (data.Length < 33 || !data[..8].SequenceEqual(Signature))
        {
            throw new PngValidationException("The upload is not a PNG image.");
        }

        var ihdrLength = BinaryPrimitives.ReadUInt32BigEndian(data.Slice(8, 4));
        if (ihdrLength != 13 || !data.Slice(12, 4).SequenceEqual("IHDR"u8))
        {
            throw new PngValidationException("The PNG has no valid IHDR chunk.");
        }

        var width = BinaryPrimitives.ReadUInt32BigEndian(data.Slice(16, 4));
        var height = BinaryPrimitives.ReadUInt32BigEndian(data.Slice(20, 4));
        if (width == 0 || height == 0 || width > int.MaxValue || height > int.MaxValue)
        {
            throw new PngValidationException("The PNG dimensions are invalid.");
        }

        if ((long)width * height > maximumPixelCount)
        {
            throw new PngValidationException("The PNG dimensions exceed the safety limit.");
        }

        var bitDepth = data[24];
        var colorType = data[25];
        if (!IsValidBitDepth(bitDepth, colorType) || data[26] != 0 || data[27] != 0 || data[28] > 1)
        {
            throw new PngValidationException("The PNG IHDR fields are invalid.");
        }

        return new PngInfo((int)width, (int)height);
    }

    private static bool IsValidBitDepth(byte bitDepth, byte colorType)
    {
        return colorType switch
        {
            0 => bitDepth is 1 or 2 or 4 or 8 or 16,
            2 => bitDepth is 8 or 16,
            3 => bitDepth is 1 or 2 or 4 or 8,
            4 => bitDepth is 8 or 16,
            6 => bitDepth is 8 or 16,
            _ => false,
        };
    }
}
