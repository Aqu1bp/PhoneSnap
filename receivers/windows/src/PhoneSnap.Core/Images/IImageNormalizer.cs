namespace PhoneSnap.Core.Images;

public interface IImageNormalizer
{
    byte[] NormalizePng(ReadOnlyMemory<byte> encodedImage);
}
