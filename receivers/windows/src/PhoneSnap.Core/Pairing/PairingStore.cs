using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace PhoneSnap.Core.Pairing;

public sealed class PairingStore
{
    private const int PairIdByteCount = 9;
    private const int TokenByteCount = 32;
    private static readonly JsonSerializerOptions SerializerOptions = new() { WriteIndented = true };

    private readonly string _path;
    private readonly ISecretProtector _protector;
    private readonly object _gate = new();
    private PairingCredentials? _cached;

    public PairingStore(string path, ISecretProtector protector)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        _path = Path.GetFullPath(path);
        _protector = protector ?? throw new ArgumentNullException(nameof(protector));
    }

    public PairingCredentials LoadOrCreate()
    {
        lock (_gate)
        {
            if (_cached is not null)
            {
                return _cached;
            }

            _cached = TryLoad() ?? CreateAndPersist();
            return _cached;
        }
    }

    public PairingCredentials Rotate()
    {
        lock (_gate)
        {
            _cached = CreateAndPersist();
            return _cached;
        }
    }

    private PairingCredentials? TryLoad()
    {
        if (!File.Exists(_path))
        {
            return null;
        }

        try
        {
            var json = File.ReadAllText(_path, Encoding.UTF8);
            var document = JsonSerializer.Deserialize<PairingDocument>(json);
            if (document is null ||
                document.Version != 1 ||
                !IsBase64Url(document.PairId, expectedLength: 12) ||
                string.IsNullOrWhiteSpace(document.ProtectedToken))
            {
                return null;
            }

            var protectedToken = Convert.FromBase64String(document.ProtectedToken);
            var token = Encoding.UTF8.GetString(_protector.Unprotect(protectedToken));
            return IsBase64Url(token, expectedLength: 43)
                ? new PairingCredentials(document.PairId, token)
                : null;
        }
        catch (Exception exception) when (exception is IOException or
                                                    UnauthorizedAccessException or
                                                    JsonException or
                                                    FormatException or
                                                    CryptographicException)
        {
            return null;
        }
    }

    private PairingCredentials CreateAndPersist()
    {
        var credentials = new PairingCredentials(
            RandomBase64Url(PairIdByteCount),
            RandomBase64Url(TokenByteCount));
        var protectedToken = _protector.Protect(Encoding.UTF8.GetBytes(credentials.Token));
        var document = new PairingDocument(
            Version: 1,
            PairId: credentials.PairId,
            ProtectedToken: Convert.ToBase64String(protectedToken));

        var directory = Path.GetDirectoryName(_path)
            ?? throw new InvalidOperationException("The pairing path has no parent directory.");
        Directory.CreateDirectory(directory);

        var temporaryPath = Path.Combine(directory, $".{Path.GetFileName(_path)}.{Guid.NewGuid():N}.tmp");
        try
        {
            var json = JsonSerializer.Serialize(document, SerializerOptions);
            File.WriteAllText(temporaryPath, json, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
            File.Move(temporaryPath, _path, overwrite: true);
        }
        finally
        {
            if (File.Exists(temporaryPath))
            {
                File.Delete(temporaryPath);
            }
        }

        return credentials;
    }

    private static string RandomBase64Url(int byteCount)
    {
        return Convert.ToBase64String(RandomNumberGenerator.GetBytes(byteCount))
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_');
    }

    private static bool IsBase64Url(string? value, int expectedLength)
    {
        return value is { Length: > 0 } &&
               value.Length == expectedLength &&
               value.All(character => char.IsAsciiLetterOrDigit(character) || character is '-' or '_');
    }

    private sealed record PairingDocument(int Version, string PairId, string ProtectedToken);
}
