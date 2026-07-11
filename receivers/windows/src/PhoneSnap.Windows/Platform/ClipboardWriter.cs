using System.Runtime.InteropServices;

namespace PhoneSnap.Windows.Platform;

internal static class ClipboardWriter
{
    public static bool WriteImageAndFile(string filePath)
    {
        var pngBytes = File.ReadAllBytes(filePath);
        using var imageStream = new MemoryStream(pngBytes, writable: false);
        using var image = Image.FromStream(imageStream, useEmbeddedColorManagement: false, validateImageData: true);
        using var bitmap = new Bitmap(image);
        using var pngStream = new MemoryStream(pngBytes, writable: false);

        var data = new DataObject();
        data.SetData(DataFormats.FileDrop, autoConvert: true, new[] { filePath });
        data.SetData(DataFormats.Bitmap, autoConvert: true, bitmap);
        data.SetData("PNG", autoConvert: false, pngStream);

        try
        {
            Clipboard.SetDataObject(data, copy: true, retryTimes: 5, retryDelay: 100);
            return true;
        }
        catch (ExternalException)
        {
            // Another process may hold the clipboard. The image remains saved.
            return false;
        }
    }
}
