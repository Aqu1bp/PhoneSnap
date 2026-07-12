using System.Security.Cryptography;
using System.Text;
using PhoneSnap.Core.Pairing;

namespace PhoneSnap.Windows.Platform;

internal sealed class DpapiSecretProtector : ISecretProtector
{
    private static readonly byte[] Entropy = SHA256.HashData(
        Encoding.UTF8.GetBytes("PhoneSnap.Windows.Pairing.v1"));

    public byte[] Protect(ReadOnlySpan<byte> plaintext)
    {
        return ProtectedData.Protect(plaintext.ToArray(), Entropy, DataProtectionScope.CurrentUser);
    }

    public byte[] Unprotect(ReadOnlySpan<byte> protectedData)
    {
        return ProtectedData.Unprotect(protectedData.ToArray(), Entropy, DataProtectionScope.CurrentUser);
    }
}
