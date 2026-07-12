using System.Diagnostics;
using PhoneSnap.Windows.Platform;
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
    private readonly Label _addressLabel = new()
    {
        Text = "Network address (choose the Wi-Fi or Ethernet shared with your iPhone)",
        AutoSize = true,
        Visible = false,
    };
    private readonly ComboBox _address = new()
    {
        Dock = DockStyle.Fill,
        DropDownStyle = ComboBoxStyle.DropDownList,
        AccessibleName = "Network address advertised to the iPhone",
        Visible = false,
    };
    private bool _updatingAddresses;

    public event Action<string>? AddressSelected;

    public SetupForm()
    {
        Text = "PhoneSnap iPhone Upload";
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        ClientSize = new Size(620, 555);
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
            RowCount = 8,
        };
        for (var row = 0; row < layout.RowCount - 1; row += 1)
        {
            layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        }
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.Controls.Add(explanation, 0, 0);
        layout.Controls.Add(_qrCode, 0, 1);
        _qrCode.Anchor = AnchorStyles.Top;
        layout.Controls.Add(_addressLabel, 0, 2);
        layout.Controls.Add(_address, 0, 3);
        layout.Controls.Add(new Label { Text = "Setup address", AutoSize = true }, 0, 4);
        layout.Controls.Add(_url, 0, 5);
        layout.Controls.Add(buttons, 0, 6);
        layout.Controls.Add(warning, 0, 7);
        Controls.Add(layout);

        _address.SelectedIndexChanged += (_, _) =>
        {
            if (!_updatingAddresses && _address.SelectedItem is SetupAddressChoice choice)
            {
                AddressSelected?.Invoke(choice.Host);
            }
        };
    }

    public void SetSetupState(Uri? setupUri, IReadOnlyList<SetupAddressChoice> addressChoices)
    {
        ArgumentNullException.ThrowIfNull(addressChoices);

        _updatingAddresses = true;
        _address.BeginUpdate();
        try
        {
            _address.Items.Clear();
            foreach (var choice in addressChoices)
            {
                _address.Items.Add(choice);
            }

            var selectedIndex = -1;
            for (var index = 0; index < addressChoices.Count; index += 1)
            {
                if (string.Equals(addressChoices[index].Host, setupUri?.Host, StringComparison.OrdinalIgnoreCase))
                {
                    selectedIndex = index;
                    break;
                }
            }
            _address.SelectedIndex = selectedIndex >= 0 ? selectedIndex : addressChoices.Count > 0 ? 0 : -1;
            _addressLabel.Visible = addressChoices.Count > 1;
            _address.Visible = addressChoices.Count > 1;
        }
        finally
        {
            _address.EndUpdate();
            _updatingAddresses = false;
        }

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
        if (Uri.TryCreate(_url.Text, UriKind.Absolute, out _) && !ClipboardWriter.WriteText(_url.Text))
        {
            MessageBox.Show(
                this,
                "The Windows clipboard is busy, so the setup address was not copied. Please try again.",
                "Address not copied",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning);
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

internal sealed record SetupAddressChoice(string Host, string Label)
{
    public override string ToString() => Label;
}
