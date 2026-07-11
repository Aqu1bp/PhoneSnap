using System.Diagnostics;
using QRCoder;

namespace PhoneSnap.Windows.UI;

internal sealed class SetupForm : Form
{
    private readonly TextBox _url = new()
    {
        ReadOnly = true,
        Dock = DockStyle.Fill,
    };
    private readonly PictureBox _qrCode = new()
    {
        Size = new Size(260, 260),
        SizeMode = PictureBoxSizeMode.Zoom,
        BackColor = Color.White,
        AccessibleName = "QR code for the iPhone upload page",
    };

    public SetupForm()
    {
        Text = "PhoneSnap iPhone Upload";
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        ClientSize = new Size(620, 500);
        ShowInTaskbar = true;

        var explanation = new Label
        {
            AutoSize = true,
            MaximumSize = new Size(520, 0),
            Text = "Scan the QR code with your iPhone Camera while both devices are on the same trusted network. " +
                   "The page lets you choose and upload a batch of screenshots without building a Shortcut.",
        };
        var warning = new Label
        {
            AutoSize = true,
            MaximumSize = new Size(520, 0),
            ForeColor = Color.DarkGoldenrod,
            Text = "If Windows Firewall asks, allow PhoneSnap on Private networks only.",
        };
        var copy = new Button { Text = "Copy address", AutoSize = true };
        copy.Click += (_, _) => CopyAddress();
        var open = new Button { Text = "Open on this PC", AutoSize = true };
        open.Click += (_, _) => OpenAddress();

        var buttons = new FlowLayoutPanel
        {
            AutoSize = true,
            FlowDirection = FlowDirection.LeftToRight,
        };
        buttons.Controls.Add(copy);
        buttons.Controls.Add(open);

        var layout = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            Padding = new Padding(20),
            ColumnCount = 1,
            RowCount = 6,
        };
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.Controls.Add(explanation);
        layout.Controls.Add(_qrCode);
        layout.SetCellPosition(_qrCode, new TableLayoutPanelCellPosition(0, 1));
        _qrCode.Anchor = AnchorStyles.Top;
        layout.Controls.Add(new Label { Text = "Setup address", AutoSize = true });
        layout.Controls.Add(_url);
        layout.Controls.Add(buttons);
        layout.Controls.Add(warning);
        Controls.Add(layout);
    }

    public void SetSetupUri(Uri? setupUri)
    {
        _url.Text = setupUri?.AbsoluteUri ?? "Receiver is not ready.";
        var oldImage = _qrCode.Image;
        _qrCode.Image = setupUri is null ? null : CreateQrCode(setupUri.AbsoluteUri);
        oldImage?.Dispose();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _qrCode.Image?.Dispose();
            _qrCode.Image = null;
        }
        base.Dispose(disposing);
    }

    private void CopyAddress()
    {
        if (Uri.TryCreate(_url.Text, UriKind.Absolute, out _))
        {
            Clipboard.SetText(_url.Text);
        }
    }

    private void OpenAddress()
    {
        if (Uri.TryCreate(_url.Text, UriKind.Absolute, out var uri))
        {
            Process.Start(new ProcessStartInfo(uri.AbsoluteUri) { UseShellExecute = true });
        }
    }

    private static Bitmap CreateQrCode(string value)
    {
        var bytes = PngByteQRCodeHelper.GetQRCode(value, QRCodeGenerator.ECCLevel.Q, 12);
        using var stream = new MemoryStream(bytes, writable: false);
        using var source = Image.FromStream(stream);
        return new Bitmap(source);
    }
}
