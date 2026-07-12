namespace PhoneSnap.Core.Images;

public sealed record SavedImage(string FilePath, int StoredByteCount);

public interface IImageStore
{
    Task<SavedImage> SaveAsync(ReadOnlyMemory<byte> encodedImage, CancellationToken cancellationToken);
}
