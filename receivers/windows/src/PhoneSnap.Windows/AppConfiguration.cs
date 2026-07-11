using PhoneSnap.Windows.Platform;

namespace PhoneSnap.Windows;

internal sealed record AppConfiguration(
    int Port,
    string SaveFolder,
    string PairingPath,
    string? AdvertisedHost)
{
    public static AppConfiguration Load()
    {
        var environment = Environment.GetEnvironmentVariables();
        var port = 8472;
        if (environment["PHONESNAP_WIRELESS_PORT"] is string portText &&
            (!int.TryParse(portText, out port) || port is <= 0 or > 65_535))
        {
            throw new InvalidOperationException("PHONESNAP_WIRELESS_PORT must be an integer from 1 to 65535.");
        }

        var pictures = Environment.GetFolderPath(Environment.SpecialFolder.MyPictures);
        var saveFolder = environment["PHONESNAP_DIR"] as string;
        if (string.IsNullOrWhiteSpace(saveFolder))
        {
            saveFolder = Path.Combine(pictures, "PhoneSnap");
        }

        var localData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var pairingPath = Path.Combine(localData, "PhoneSnap", "pairing.json");
        return new AppConfiguration(
            port,
            Path.GetFullPath(saveFolder),
            pairingPath,
            LanAddressProvider.GetPreferredIPv4()?.ToString());
    }
}
