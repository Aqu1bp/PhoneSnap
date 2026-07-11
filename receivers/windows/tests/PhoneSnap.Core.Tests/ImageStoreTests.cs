using System.Buffers.Binary;
using PhoneSnap.Core.Images;

namespace PhoneSnap.Core.Tests;

public sealed class ImageStoreTests
{
    [Fact]
    public async Task ConcurrentSavesUseUniqueAtomicNames()
    {
        using var temporary = new TemporaryDirectory();
        var store = new ImageStore(
            temporary.Path,
            new ValidatingNormalizer(),
            new FixedTimeProvider(new DateTimeOffset(2026, 7, 11, 12, 34, 56, TimeSpan.Zero)));

        var saved = await Task.WhenAll(Enumerable.Range(0, 8)
            .Select(_ => store.SaveAsync(TestPng.OneByOne, CancellationToken.None)));

        Assert.Equal(8, saved.Select(item => item.FilePath).Distinct(StringComparer.Ordinal).Count());
        Assert.All(saved, item => Assert.True(File.Exists(item.FilePath)));
        Assert.Empty(Directory.GetFiles(temporary.Path, "*.tmp"));
    }

    [Fact]
    public async Task PixelBombIsRejectedBeforeNormalizerRuns()
    {
        using var temporary = new TemporaryDirectory();
        var normalizer = new ValidatingNormalizer();
        var store = new ImageStore(temporary.Path, normalizer);
        var bytes = TestPng.OneByOne.ToArray();
        BinaryPrimitives.WriteUInt32BigEndian(bytes.AsSpan(16, 4), 10_000);
        BinaryPrimitives.WriteUInt32BigEndian(bytes.AsSpan(20, 4), 10_000);

        await Assert.ThrowsAsync<PngValidationException>(() =>
            store.SaveAsync(bytes, CancellationToken.None));
        Assert.Equal(0, normalizer.CallCount);
        Assert.Empty(Directory.GetFiles(temporary.Path));
    }
}
