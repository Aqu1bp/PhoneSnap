using System.Net;
using System.Security.Cryptography;
using System.Text.Json;
using PhoneSnap.Core.Pairing;

namespace PhoneSnap.Core.Receiver;

internal sealed record SetupPageDocument(string Html, string ContentSecurityPolicy);

internal static class SetupPage
{
    public static SetupPageDocument Render(Uri uploadUri, PairingCredentials pairing)
    {
        var endpointText = WebUtility.HtmlEncode(uploadUri.AbsoluteUri);
        var endpointJson = JsonSerializer.Serialize(uploadUri.AbsoluteUri);
        var tokenJson = JsonSerializer.Serialize(pairing.Token);
        var nonce = Convert.ToBase64String(RandomNumberGenerator.GetBytes(18));
        var contentSecurityPolicy =
            $"default-src 'none'; script-src 'nonce-{nonce}'; style-src 'unsafe-inline'; " +
            "img-src blob:; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";

        var html = $$"""
            <!doctype html>
            <html lang="en">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width,initial-scale=1">
              <title>Send screenshots to PhoneSnap</title>
              <style>
                :root { color-scheme: light dark; font: 16px system-ui, sans-serif; }
                body { max-width: 42rem; margin: 3rem auto; padding: 0 1.25rem; line-height: 1.5; }
                code { overflow-wrap: anywhere; }
                .picker { display: grid; gap: 1rem; padding: 1.25rem; border: 1px solid #8886; border-radius: .75rem; }
                button { min-height: 2.75rem; font: inherit; font-weight: 600; }
                progress { width: 100%; }
                .endpoint { color: #777; font-size: .85rem; }
                .warning { padding: .8rem; border-left: .25rem solid #d88900; background: #d8890018; }
                #status { min-height: 1.5rem; white-space: pre-wrap; }
              </style>
            </head>
            <body>
              <h1>Send screenshots to PhoneSnap</h1>
              <p>Choose screenshots from Photos or Files. They are converted to PNG when needed and uploaded one at a time to this PC.</p>
              <section class="picker">
                <label for="files"><strong>Screenshots</strong></label>
                <input id="files" type="file" multiple accept="image/*">
                <button id="upload" type="button" disabled>Upload selected screenshots</button>
                <progress id="progress" value="0" max="1" hidden></progress>
                <output id="status" aria-live="polite">Choose one or more images.</output>
              </section>
              <p class="endpoint">Receiver: <code>{{endpointText}}</code></p>
              <p class="warning">This page contains a temporary view of your receiver credential. Use it only on a local network you trust, then close the tab.</p>
              <script nonce="{{nonce}}">
                (() => {
                  'use strict';
                  const endpoint = {{endpointJson}};
                  const token = {{tokenJson}};
                  const files = document.getElementById('files');
                  const upload = document.getElementById('upload');
                  const progress = document.getElementById('progress');
                  const status = document.getElementById('status');

                  files.addEventListener('change', () => {
                    upload.disabled = files.files.length === 0;
                    status.textContent = files.files.length === 0
                      ? 'Choose one or more images.'
                      : `${files.files.length} image${files.files.length === 1 ? '' : 's'} ready.`;
                  });

                  function pngName(name) {
                    const base = name.replace(/\.[^.]*$/, '') || 'Screenshot';
                    return `${base}.png`;
                  }

                  async function asPng(file) {
                    if (file.type.toLowerCase() === 'image/png') {
                      return new File([file], pngName(file.name), { type: 'image/png' });
                    }

                    const objectUrl = URL.createObjectURL(file);
                    try {
                      const image = new Image();
                      image.decoding = 'async';
                      const loaded = new Promise((resolve, reject) => {
                        image.onload = resolve;
                        image.onerror = () => reject(new Error(`Could not decode ${file.name}.`));
                      });
                      image.src = objectUrl;
                      await loaded;

                      if (image.naturalWidth * image.naturalHeight > 50000000) {
                        throw new Error(`${file.name} exceeds PhoneSnap's 50 megapixel safety limit.`);
                      }

                      const canvas = document.createElement('canvas');
                      canvas.width = image.naturalWidth;
                      canvas.height = image.naturalHeight;
                      const context = canvas.getContext('2d');
                      if (!context || canvas.width === 0 || canvas.height === 0) {
                        throw new Error(`Could not convert ${file.name}.`);
                      }
                      context.drawImage(image, 0, 0);
                      const blob = await new Promise((resolve, reject) => {
                        canvas.toBlob(value => value ? resolve(value) : reject(new Error(`Could not convert ${file.name}.`)), 'image/png');
                      });
                      return new File([blob], pngName(file.name), { type: 'image/png' });
                    } finally {
                      URL.revokeObjectURL(objectUrl);
                    }
                  }

                  upload.addEventListener('click', async () => {
                    const selected = Array.from(files.files);
                    if (selected.length === 0) return;

                    upload.disabled = true;
                    files.disabled = true;
                    progress.hidden = false;
                    progress.max = selected.length;
                    progress.value = 0;
                    const results = [];
                    let failed = 0;

                    try {
                      for (let index = 0; index < selected.length; index += 1) {
                        const source = selected[index];
                        try {
                          status.textContent = `Preparing ${index + 1} of ${selected.length}: ${source.name}`;
                          const png = await asPng(source);
                          const body = new FormData();
                          body.append('file', png, png.name);
                          const response = await fetch(endpoint, {
                            method: 'POST',
                            headers: { Authorization: `Bearer ${token}` },
                            body,
                            cache: 'no-store',
                            credentials: 'omit',
                            redirect: 'error'
                          });
                          if (!response.ok) {
                            const detail = await response.text();
                            throw new Error(`${response.status}: ${detail}`);
                          }
                          results.push(`✓ ${source.name}`);
                        } catch (error) {
                          failed += 1;
                          const detail = error instanceof Error ? error.message : 'upload failed';
                          results.push(`✗ ${source.name} — ${detail}`);
                        } finally {
                          progress.value = index + 1;
                          status.textContent = results.join('\n');
                        }
                      }
                      results.push(failed === 0
                        ? `Uploaded all ${selected.length} screenshots.`
                        : `Uploaded ${selected.length - failed}; ${failed} failed.`);
                      status.textContent = results.join('\n');
                      files.value = '';
                    } finally {
                      files.disabled = false;
                      upload.disabled = files.files.length === 0;
                    }
                  });
                })();
              </script>
            </body>
            </html>
            """;

        return new SetupPageDocument(html, contentSecurityPolicy);
    }
}
