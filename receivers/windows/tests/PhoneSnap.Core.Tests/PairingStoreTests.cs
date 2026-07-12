using PhoneSnap.Core.Pairing;

namespace PhoneSnap.Core.Tests;

public sealed class PairingStoreTests
{
    [Fact]
    public void LoadOrCreatePersistsProtectedCredentials()
    {
        using var temporary = new TemporaryDirectory();
        var path = Path.Combine(temporary.Path, "state", "pairing.json");
        var first = new PairingStore(path, new TestSecretProtector()).LoadOrCreate();
        var second = new PairingStore(path, new TestSecretProtector()).LoadOrCreate();

        Assert.Equal(12, first.PairId.Length);
        Assert.Equal(43, first.Token.Length);
        Assert.Equal(first, second);
        Assert.DoesNotContain(first.Token, File.ReadAllText(path), StringComparison.Ordinal);
    }

    [Fact]
    public void RotateInvalidatesPreviousCredentials()
    {
        using var temporary = new TemporaryDirectory();
        var store = new PairingStore(Path.Combine(temporary.Path, "pairing.json"), new TestSecretProtector());
        var first = store.LoadOrCreate();

        var rotated = store.Rotate();

        Assert.NotEqual(first.PairId, rotated.PairId);
        Assert.NotEqual(first.Token, rotated.Token);
        Assert.Equal(rotated, new PairingStore(
            Path.Combine(temporary.Path, "pairing.json"),
            new TestSecretProtector()).LoadOrCreate());
    }

    [Fact]
    public void MalformedStateIsReplaced()
    {
        using var temporary = new TemporaryDirectory();
        var path = Path.Combine(temporary.Path, "pairing.json");
        File.WriteAllText(path, "not-json");

        var credentials = new PairingStore(path, new TestSecretProtector()).LoadOrCreate();

        Assert.Equal(12, credentials.PairId.Length);
        Assert.Contains("protectedToken", File.ReadAllText(path), StringComparison.OrdinalIgnoreCase);
    }
}
