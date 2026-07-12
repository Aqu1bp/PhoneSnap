using System.Globalization;

namespace PhoneSnap.Core.Images;

public sealed class ImageStore : IImageStore
{
    private readonly string _folder;
    private readonly IImageNormalizer _normalizer;
    private readonly TimeProvider _timeProvider;
    private readonly long _maximumPixelCount;
    private readonly object _commitGate = new();

    public ImageStore(
        string folder,
        IImageNormalizer normalizer,
        TimeProvider? timeProvider = null,
        long maximumPixelCount = PngValidator.DefaultMaximumPixelCount)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(folder);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maximumPixelCount);
        _folder = Path.GetFullPath(folder);
        _normalizer = normalizer ?? throw new ArgumentNullException(nameof(normalizer));
        _timeProvider = timeProvider ?? TimeProvider.System;
        _maximumPixelCount = maximumPixelCount;
    }

    public string Folder => _folder;

    public async Task<SavedImage> SaveAsync(
        ReadOnlyMemory<byte> encodedImage,
        CancellationToken cancellationToken)
    {
        if (encodedImage.IsEmpty)
        {
            throw new PngValidationException("The upload body is empty.");
        }

        cancellationToken.ThrowIfCancellationRequested();
        _ = PngValidator.ValidateHeader(encodedImage.Span, _maximumPixelCount);
        var normalized = await _normalizer.NormalizePngAsync(encodedImage, cancellationToken).ConfigureAwait(false);
        _ = PngValidator.ValidateHeader(normalized, _maximumPixelCount);
        cancellationToken.ThrowIfCancellationRequested();

        Directory.CreateDirectory(_folder);
        var temporaryPath = Path.Combine(_folder, $".phonesnap-{Guid.NewGuid():N}.tmp");
        try
        {
            using (var stream = new FileStream(
                       temporaryPath,
                       FileMode.CreateNew,
                       FileAccess.Write,
                       FileShare.None,
                       bufferSize: 64 * 1024,
                       FileOptions.WriteThrough))
            {
                stream.Write(normalized);
                stream.Flush(flushToDisk: true);
            }

            lock (_commitGate)
            {
                for (var suffix = 1; suffix <= 10_000; suffix++)
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    var candidate = CandidatePath(suffix);
                    if (File.Exists(candidate))
                    {
                        continue;
                    }

                    File.Move(temporaryPath, candidate, overwrite: false);
                    return new SavedImage(candidate, normalized.Length);
                }

                var fallback = Path.Combine(_folder, $"Screenshot {Guid.NewGuid():N}.png");
                File.Move(temporaryPath, fallback, overwrite: false);
                return new SavedImage(fallback, normalized.Length);
            }
        }
        finally
        {
            if (File.Exists(temporaryPath))
            {
                File.Delete(temporaryPath);
            }
        }
    }

    private string CandidatePath(int suffix)
    {
        var timestamp = _timeProvider.GetLocalNow().ToString(
            "yyyy-MM-dd 'at' HH.mm.ss.fff",
            CultureInfo.InvariantCulture);
        var suffixText = suffix == 1 ? string.Empty : $" ({suffix})";
        return Path.Combine(_folder, $"Screenshot {timestamp}{suffixText}.png");
    }
}
