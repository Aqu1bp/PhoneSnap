using System.Buffers.Binary;
using PhoneSnap.Core.Images;

namespace PhoneSnap.Core.Tests;

public sealed class PngValidatorTests
{
    [Fact]
    public void ReadsValidHeader()
    {
        var info = PngValidator.ValidateHeader(TestPng.OneByOne);

        Assert.Equal(new PngInfo(1, 1), info);
    }

    [Fact]
    public void RejectsNonPngInput()
    {
        Assert.Throws<PngValidationException>(() => PngValidator.ValidateHeader("not an image"u8));
    }

    [Fact]
    public void RejectsDeclaredPixelBomb()
    {
        var bytes = TestPng.OneByOne.ToArray();
        BinaryPrimitives.WriteUInt32BigEndian(bytes.AsSpan(16, 4), 10_000);
        BinaryPrimitives.WriteUInt32BigEndian(bytes.AsSpan(20, 4), 10_000);

        Assert.Throws<PngValidationException>(() => PngValidator.ValidateHeader(bytes));
    }
}
