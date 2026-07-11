using System.Diagnostics;

namespace PhoneSnap.Windows.UI;

internal sealed class RecentImagesForm : Form
{
    private const int MaximumItems = 20;
    private readonly FlowLayoutPanel _images = new()
    {
        Dock = DockStyle.Fill,
        AutoScroll = true,
        FlowDirection = FlowDirection.LeftToRight,
        WrapContents = false,
        Padding = new Padding(10),
    };

    public RecentImagesForm()
    {
        Text = "Recent PhoneSnap Screenshots";
        TopMost = true;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        MinimumSize = new Size(360, 245);
        ClientSize = new Size(720, 235);
        Controls.Add(_images);
        FormClosing += (_, eventArgs) =>
        {
            if (eventArgs.CloseReason == CloseReason.UserClosing)
            {
                eventArgs.Cancel = true;
                Hide();
            }
        };
    }

    public bool HasImages => _images.Controls.Count > 0;

    public void AddImage(string filePath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(filePath);
        if (!File.Exists(filePath))
        {
            return;
        }

        var card = CreateCard(filePath);
        _images.Controls.Add(card);
        while (_images.Controls.Count > MaximumItems)
        {
            var oldest = _images.Controls[0];
            _images.Controls.RemoveAt(0);
            DisposeCard(oldest);
        }

        ShowRecent();
        _images.ScrollControlIntoView(card);
    }

    public void ShowRecent()
    {
        PositionNearWorkArea();
        if (!Visible)
        {
            Show();
        }
        BringToFront();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            foreach (var card in _images.Controls.Cast<Control>().ToArray())
            {
                DisposeCard(card);
            }
        }
        base.Dispose(disposing);
    }

    private static FlowLayoutPanel CreateCard(string filePath)
    {
        var picture = new PictureBox
        {
            Size = new Size(150, 155),
            SizeMode = PictureBoxSizeMode.Zoom,
            BackColor = Color.FromArgb(32, 32, 32),
            Cursor = Cursors.Hand,
            AccessibleName = $"Drag {Path.GetFileName(filePath)}",
            Image = LoadDetachedImage(filePath),
        };
        picture.MouseDown += (_, eventArgs) =>
        {
            if (eventArgs.Button == MouseButtons.Left)
            {
                var data = new DataObject();
                data.SetData(DataFormats.FileDrop, autoConvert: true, new[] { filePath });
                picture.DoDragDrop(data, DragDropEffects.Copy);
            }
        };
        picture.DoubleClick += (_, _) => OpenFile(filePath);

        var label = new Label
        {
            AutoEllipsis = true,
            Text = Path.GetFileName(filePath),
            Width = 150,
            Height = 32,
            TextAlign = ContentAlignment.MiddleCenter,
        };
        var card = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            AutoSize = true,
            Margin = new Padding(6),
            AccessibleName = Path.GetFileName(filePath),
        };
        card.Controls.Add(picture);
        card.Controls.Add(label);
        return card;
    }

    private static Bitmap LoadDetachedImage(string filePath)
    {
        using var stream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.Read);
        using var source = Image.FromStream(stream, useEmbeddedColorManagement: false, validateImageData: true);
        return new Bitmap(source);
    }

    private static void DisposeCard(Control card)
    {
        foreach (var picture in card.Controls.OfType<PictureBox>())
        {
            picture.Image?.Dispose();
            picture.Image = null;
        }
        card.Dispose();
    }

    private static void OpenFile(string filePath)
    {
        if (File.Exists(filePath))
        {
            Process.Start(new ProcessStartInfo(filePath) { UseShellExecute = true });
        }
    }

    private void PositionNearWorkArea()
    {
        var workArea = Screen.FromPoint(Cursor.Position).WorkingArea;
        Location = new Point(
            Math.Max(workArea.Left, workArea.Right - Width - 20),
            Math.Max(workArea.Top, workArea.Bottom - Height - 20));
    }
}
