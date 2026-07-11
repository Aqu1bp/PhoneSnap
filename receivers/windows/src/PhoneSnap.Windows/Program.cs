namespace PhoneSnap.Windows;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        FileStream instanceLock;
        try
        {
            var localData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            var stateDirectory = Path.Combine(localData, "PhoneSnap");
            Directory.CreateDirectory(stateDirectory);
            instanceLock = new FileStream(
                Path.Combine(stateDirectory, "app.lock"),
                FileMode.OpenOrCreate,
                FileAccess.ReadWrite,
                FileShare.None);
        }
        catch (IOException)
        {
            MessageBox.Show(
                "PhoneSnap is already running for this Windows user, or its instance lock is unavailable.",
                "PhoneSnap",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);
            return;
        }
        catch (Exception exception) when (exception is UnauthorizedAccessException or NotSupportedException)
        {
            ShowStartupFailure(exception);
            return;
        }

        using (instanceLock)
        {
            try
            {
                Application.Run(new PhoneSnapApplicationContext());
            }
            catch (Exception exception)
            {
                ShowStartupFailure(exception);
            }
        }
    }

    private static void ShowStartupFailure(Exception exception)
    {
        MessageBox.Show(
            $"PhoneSnap could not start.\n\n{exception.Message}",
            "PhoneSnap",
            MessageBoxButtons.OK,
            MessageBoxIcon.Error);
    }
}
