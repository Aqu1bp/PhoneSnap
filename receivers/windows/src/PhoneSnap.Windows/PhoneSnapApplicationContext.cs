using System.Diagnostics;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using PhoneSnap.Core.Delivery;
using PhoneSnap.Core.Images;
using PhoneSnap.Core.Pairing;
using PhoneSnap.Core.Receiver;
using PhoneSnap.Windows.Platform;
using PhoneSnap.Windows.UI;

namespace PhoneSnap.Windows;

internal sealed class PhoneSnapApplicationContext : ApplicationContext
{
    private readonly AppConfiguration _configuration;
    private readonly PairingStore _pairingStore;
    private readonly ImageStore _imageStore;
    private readonly ReceiverServer _receiver;
    private readonly Control _dispatcher = new();
    private readonly Icon _icon = new(SystemIcons.Application, 32, 32);
    private readonly ToolStripMenuItem _statusItem = new("Receiver: starting") { Enabled = false };
    private readonly ToolStripMenuItem _setupItem;
    private readonly ToolStripMenuItem _showLastItem;
    private readonly NotifyIcon _trayIcon;
    private SetupForm? _setupForm;
    private RecentImagesForm? _recentImagesForm;
    private string? _lastFilePath;
    private bool _disposed;

    public PhoneSnapApplicationContext()
    {
        _configuration = AppConfiguration.Load();
        _pairingStore = new PairingStore(_configuration.PairingPath, new DpapiSecretProtector());
        var pairing = _pairingStore.LoadOrCreate();
        const long maximumPixels = PngValidator.DefaultMaximumPixelCount;
        _imageStore = new ImageStore(
            _configuration.SaveFolder,
            new WindowsPngNormalizer(maximumPixels),
            maximumPixelCount: maximumPixels);
        _receiver = new ReceiverServer(
            new ReceiverOptions
            {
                Port = _configuration.Port,
                AdvertisedHost = _configuration.AdvertisedHost,
            },
            pairing,
            _imageStore);

        _ = _dispatcher.Handle;
        _setupItem = new ToolStripMenuItem("Open iPhone Upload Page…", null, (_, _) => ShowSetup())
        {
            Enabled = false,
        };
        _showLastItem = new ToolStripMenuItem("Show Last Screenshot", null, (_, _) => ShowLast())
        {
            Enabled = false,
        };
        var openFolder = new ToolStripMenuItem("Open Save Folder", null, (_, _) => OpenSaveFolder());
        var quit = new ToolStripMenuItem("Quit PhoneSnap", null, async (_, _) => await QuitAsync());
        var menu = new ContextMenuStrip();
        menu.Items.AddRange([
            _statusItem,
            new ToolStripSeparator(),
            _setupItem,
            _showLastItem,
            openFolder,
            new ToolStripSeparator(),
            quit,
        ]);

        _trayIcon = new NotifyIcon
        {
            Icon = _icon,
            Text = "PhoneSnap for Windows",
            ContextMenuStrip = menu,
            Visible = true,
        };
        _trayIcon.DoubleClick += (_, _) => ShowSetup();

        _receiver.StateChanged += ReceiverStateChanged;
        _receiver.UploadDelivered += UploadDelivered;
        NetworkChange.NetworkAddressChanged += NetworkAddressChanged;
        _ = StartReceiverAsync();
    }

    protected override void ExitThreadCore()
    {
        if (!_disposed)
        {
            _disposed = true;
            _trayIcon.Visible = false;
            NetworkChange.NetworkAddressChanged -= NetworkAddressChanged;
            _receiver.StateChanged -= ReceiverStateChanged;
            _receiver.UploadDelivered -= UploadDelivered;
            _receiver.DisposeAsync().AsTask().GetAwaiter().GetResult();
            _setupForm?.Dispose();
            _recentImagesForm?.Dispose();
            _trayIcon.Dispose();
            _icon.Dispose();
            _dispatcher.Dispose();
        }

        base.ExitThreadCore();
    }

    private async Task StartReceiverAsync()
    {
        try
        {
            await _receiver.StartAsync();
        }
        catch (Exception exception)
        {
            OnUi(() =>
            {
                _statusItem.Text = $"Receiver unavailable: {exception.Message}";
                _trayIcon.ShowBalloonTip(5000, "PhoneSnap receiver unavailable", exception.Message, ToolTipIcon.Error);
            });
        }
    }

    private void ReceiverStateChanged(object? sender, ReceiverStateChangedEventArgs eventArgs)
    {
        OnUi(() => UpdateReceiverUi(eventArgs.State));
    }

    private void NetworkAddressChanged(object? sender, EventArgs eventArgs)
    {
        RefreshAdvertisedAddress();
    }

    private void RefreshAdvertisedAddress()
    {
        string? host;
        try
        {
            host = LanAddressProvider.GetPreferredIPv4()?.ToString();
        }
        catch (NetworkInformationException)
        {
            host = null;
        }

        _receiver.UpdateAdvertisedHost(host);
        OnUi(() => UpdateReceiverUi(_receiver.State));
    }

    private void UpdateReceiverUi(ReceiverState state)
    {
        var setupUri = _receiver.SetupUri;
        _statusItem.Text = state.Activity switch
        {
            ReceiverActivity.Starting => "Receiver: starting",
            ReceiverActivity.Ready when setupUri is not null => $"Receiver: ready on {_receiver.BaseUri}",
            ReceiverActivity.Ready => "Receiver: ready; connect this PC to a LAN",
            ReceiverActivity.Failed => $"Receiver unavailable: {state.Error}",
            _ => "Receiver: stopped",
        };
        _setupItem.Enabled = state.Activity == ReceiverActivity.Ready && setupUri is not null;
        if (_setupForm is { IsDisposed: false })
        {
            _setupForm.SetSetupUri(setupUri);
        }
    }

    private void UploadDelivered(object? sender, UploadDeliveredEventArgs eventArgs)
    {
        OnUi(() =>
        {
            _lastFilePath = eventArgs.Image.FilePath;
            _showLastItem.Enabled = true;
            var clipboardUpdated = false;
            try
            {
                clipboardUpdated = ClipboardWriter.WriteImageAndFile(eventArgs.Image.FilePath);
            }
            catch (Exception exception) when (exception is ArgumentException or
                                                        IOException or
                                                        ExternalException or
                                                        OutOfMemoryException)
            {
                clipboardUpdated = false;
            }

            var previewUpdated = false;
            try
            {
                _recentImagesForm ??= new RecentImagesForm();
                _recentImagesForm.AddImage(eventArgs.Image.FilePath);
                previewUpdated = true;
            }
            catch (Exception exception) when (exception is ArgumentException or IOException or ExternalException or OutOfMemoryException)
            {
                previewUpdated = false;
            }

            var result = (clipboardUpdated, previewUpdated) switch
            {
                (true, true) => Path.GetFileName(eventArgs.Image.FilePath),
                (false, true) => $"{Path.GetFileName(eventArgs.Image.FilePath)} saved; the clipboard is busy.",
                (true, false) => $"{Path.GetFileName(eventArgs.Image.FilePath)} saved; its preview could not be shown.",
                _ => $"{Path.GetFileName(eventArgs.Image.FilePath)} saved; clipboard and preview updates failed.",
            };
            _trayIcon.ShowBalloonTip(
                4000,
                "Screenshot received",
                result,
                clipboardUpdated && previewUpdated ? ToolTipIcon.Info : ToolTipIcon.Warning);
        });
    }

    private void ShowSetup()
    {
        RefreshAdvertisedAddress();
        if (_receiver.SetupUri is null)
        {
            _trayIcon.ShowBalloonTip(
                4000,
                "No reachable LAN address",
                "Connect this PC to the same private network as the iPhone, then try again.",
                ToolTipIcon.Warning);
            return;
        }

        if (_setupForm is null || _setupForm.IsDisposed)
        {
            _setupForm = new SetupForm();
        }
        _setupForm.SetSetupUri(_receiver.SetupUri);
        _setupForm.Show();
        _setupForm.Activate();
    }

    private void ShowLast()
    {
        if (_lastFilePath is not null && File.Exists(_lastFilePath))
        {
            try
            {
                _recentImagesForm ??= new RecentImagesForm();
                if (!_recentImagesForm.HasImages)
                {
                    _recentImagesForm.AddImage(_lastFilePath);
                }
                _recentImagesForm.ShowRecent();
            }
            catch (Exception exception) when (exception is ArgumentException or IOException or ExternalException or OutOfMemoryException)
            {
                _trayIcon.ShowBalloonTip(
                    4000,
                    "Preview unavailable",
                    "The screenshot remains saved and can be opened from the save folder.",
                    ToolTipIcon.Warning);
            }
        }
    }

    private void OpenSaveFolder()
    {
        Directory.CreateDirectory(_imageStore.Folder);
        Process.Start(new ProcessStartInfo(_imageStore.Folder) { UseShellExecute = true });
    }

    private async Task QuitAsync()
    {
        _setupItem.Enabled = false;
        await _receiver.StopAsync();
        ExitThread();
    }

    private void OnUi(Action action)
    {
        if (_dispatcher.IsDisposed)
        {
            return;
        }

        if (_dispatcher.InvokeRequired)
        {
            try
            {
                _dispatcher.BeginInvoke(action);
            }
            catch (InvalidOperationException) when (_dispatcher.IsDisposed || _disposed)
            {
                // Shutdown won the race with a background receiver/network event.
            }
        }
        else
        {
            action();
        }
    }
}
