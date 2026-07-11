namespace PhoneSnap.Core.Images;

public sealed class PngValidationException : Exception
{
    public PngValidationException(string message)
        : base(message)
    {
    }

    public PngValidationException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}
