using PhoneSnap.Core.Images;

namespace PhoneSnap.Core.Delivery;

public sealed class UploadDeliveredEventArgs : EventArgs
{
    public UploadDeliveredEventArgs(SavedImage image, int acceptedByteCount)
    {
        Image = image ?? throw new ArgumentNullException(nameof(image));
        AcceptedByteCount = acceptedByteCount;
    }

    public SavedImage Image { get; }

    public int AcceptedByteCount { get; }
}
