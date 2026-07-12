using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using PhoneSnap.Core.Images;

namespace PhoneSnap.Windows.Platform;

internal sealed class WindowsPngNormalizer
{
    private readonly long _maximumPixelCount;

    public WindowsPngNormalizer(long maximumPixelCount = PngValidator.DefaultMaximumPixelCount)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maximumPixelCount);
        _maximumPixelCount = maximumPixelCount;
    }

    public byte[] NormalizePng(ReadOnlyMemory<byte> encodedImage)
    {
        var declared = PngValidator.ValidateHeader(encodedImage.Span, _maximumPixelCount);
        try
        {
            using var input = new MemoryStream(encodedImage.ToArray(), writable: false);
            using var source = Image.FromStream(input, useEmbeddedColorManagement: false, validateImageData: true);
            if (source.Width != declared.Width || source.Height != declared.Height ||
                (long)source.Width * source.Height > _maximumPixelCount)
            {
                throw new PngValidationException("The decoded PNG dimensions do not match its header.");
            }

            using var bitmap = new Bitmap(source.Width, source.Height, PixelFormat.Format32bppArgb);
            using (var graphics = Graphics.FromImage(bitmap))
            {
                graphics.CompositingMode = CompositingMode.SourceCopy;
                graphics.DrawImage(
                    source,
                    new Rectangle(0, 0, bitmap.Width, bitmap.Height),
                    0,
                    0,
                    source.Width,
                    source.Height,
                    GraphicsUnit.Pixel);
            }

            using var output = new MemoryStream();
            bitmap.Save(output, ImageFormat.Png);
            var normalized = output.ToArray();
            _ = PngValidator.ValidateHeader(normalized, _maximumPixelCount);
            return normalized;
        }
        catch (PngValidationException)
        {
            throw;
        }
        catch (Exception exception) when (exception is ArgumentException or
                                                    ExternalException or
                                                    OutOfMemoryException)
        {
            throw new PngValidationException("The PNG could not be decoded.", exception);
        }
    }
}
