namespace PhoneSnap.Core.Images;

public interface IImageNormalizer
{
    Task<byte[]> NormalizePngAsync(
        ReadOnlyMemory<byte> encodedImage,
        CancellationToken cancellationToken);
}
