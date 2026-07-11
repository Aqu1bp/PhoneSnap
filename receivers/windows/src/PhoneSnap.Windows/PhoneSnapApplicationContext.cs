using System.Diagnostics;
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
                MaximumPixelCount = (int)maximumPixels,
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
        _ = StartReceiverAsync();
    }

    protected override void ExitThreadCore()
    {
        if (!_disposed)
        {
            _disposed = true;
            _trayIcon.Visible = false;
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
        OnUi(() =>
        {
            _statusItem.Text = eventArgs.State.Activity switch
            {
                ReceiverActivity.Starting => "Receiver: starting",
                ReceiverActivity.Ready => $"Receiver: ready on {_receiver.BaseUri}",
                ReceiverActivity.Failed => $"Receiver unavailable: {eventArgs.State.Error}",
                _ => "Receiver: stopped",
            };
            _setupItem.Enabled = eventArgs.State.Activity == ReceiverActivity.Ready;
            if (_setupForm is { IsDisposed: false })
            {
                _setupForm.SetSetupUri(_receiver.SetupUri);
            }
        });
    }

    private void UploadDelivered(object? sender, UploadDeliveredEventArgs eventArgs)
    {
        OnUi(() =>
        {
            _lastFilePath = eventArgs.Image.FilePath;
            _showLastItem.Enabled = true;
            try
            {
                ClipboardWriter.WriteImageAndFile(eventArgs.Image.FilePath);
            }
            catch (Exception exception) when (exception is ArgumentException or IOException)
            {
                _trayIcon.ShowBalloonTip(3000, "Screenshot saved", "The Windows clipboard could not be updated.", ToolTipIcon.Warning);
            }
            _recentImagesForm ??= new RecentImagesForm();
            _recentImagesForm.AddImage(eventArgs.Image.FilePath);
            _trayIcon.ShowBalloonTip(
                3000,
                "Screenshot received",
                Path.GetFileName(eventArgs.Image.FilePath),
                ToolTipIcon.Info);
        });
    }

    private void ShowSetup()
    {
        if (_receiver.SetupUri is null)
        {
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
            _recentImagesForm ??= new RecentImagesForm();
            if (!_recentImagesForm.HasImages)
            {
                _recentImagesForm.AddImage(_lastFilePath);
            }
            _recentImagesForm.ShowRecent();
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
            _dispatcher.BeginInvoke(action);
        }
        else
        {
            action();
        }
    }
}
