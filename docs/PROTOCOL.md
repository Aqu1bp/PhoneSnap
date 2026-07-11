# PhoneSnap Local Upload Protocol v1

Status: stable

PhoneSnap's platform boundary is a small HTTP upload protocol. Screenshot
sources can run on any phone or development tool, and receivers can run on any
desktop operating system, as long as both sides implement this contract.

The setup pages and generated Apple Shortcut are macOS receiver features. They
are not part of the portable upload protocol.

## Transport

- HTTP/1.1 over the local network.
- One screenshot per request.
- A request must include `Content-Length`.
- `Transfer-Encoding: chunked` is not supported.
- The maximum request body is 32 MiB.
- A sender must not follow redirects when uploading credentials and image data.

Version 1 uses plain HTTP because the generated iOS Shortcut cannot establish a
pinned trust relationship with an ephemeral local certificate. The bearer
credential is therefore observable by other parties that can inspect LAN
traffic. Users must use wired capture instead on untrusted networks.

## Pairing Material

A receiver provisions:

- `pairId`: an unguessable URL capability identifying a pairing.
- `token`: a high-entropy bearer credential authorizing uploads.

How those values reach a sender is platform-specific. The macOS receiver puts
them into a locally generated signed Shortcut. A native sender can obtain them
from a QR code or another explicit user-approved pairing flow.

Neither value may be advertised through DNS-SD, Bonjour, broadcast discovery,
analytics, or logs. A future discovery record may advertise a receiver's name,
port, and supported protocol versions, but never pairing material.

## Upload Request

```http
POST /api/v1/upload/<pairId> HTTP/1.1
Host: <receiver-host>:<receiver-port>
Authorization: Bearer <token>
Content-Type: image/png
Content-Length: <byte-count>

<image bytes>
```

The only accepted credential location is the `Authorization` header. Senders
must not place a token in the URL, query string, filename, or metadata headers.

Receivers accept either:

1. A raw image body with an appropriate `image/*` content type. PNG is the
   preferred interoperable format; JPEG and HEIC may be accepted when the
   receiver's image decoder supports them.
2. `multipart/form-data` containing an image part. The part should have an
   `image/*` content type and a filename.

A receiver must decode the content as an image before treating the request as
successful. PhoneSnap normalizes accepted input to PNG before saving it.

### Optional Metadata

Version 1 receivers must tolerate unknown request headers. Senders may provide:

```http
X-PhoneSnap-Source: android-adb
X-PhoneSnap-Captured-At: 2026-07-11T12:34:56.789Z
X-PhoneSnap-Device-ID: <sender-generated-installation-id>
X-PhoneSnap-Filename: Screenshot_20260711.png
```

These fields are advisory. A receiver may ignore them and must not trust them
for authorization, filesystem paths, or deduplication. `X-PhoneSnap-Device-ID`
must be an application-generated identifier, not a hardware identifier.

## Success Response

```http
HTTP/1.1 200 OK
Content-Type: application/json

{"ok":true,"bytes":12345}
```

`bytes` is the number of extracted image bytes accepted from the request, not
necessarily the size of the normalized PNG stored by the receiver.

The same image can be uploaded more than once. A receiver may deduplicate it,
but every valid request still returns success and should re-surface the image
in the user interface. The macOS receiver deduplicates wireless uploads by
SHA-256 for the lifetime of its process.

## Error Responses

| Status | Meaning |
| --- | --- |
| `400 Bad Request` | Malformed/incomplete request or empty upload body. |
| `401 Unauthorized` | Missing or invalid bearer credential. |
| `404 Not Found` | Unknown route or pair ID. |
| `405 Method Not Allowed` | Upload route used with a method other than `POST`. |
| `411 Length Required` | Authenticated upload omitted `Content-Length`. |
| `413 Payload Too Large` | Declared body exceeds 32 MiB. |
| `415 Unsupported Media Type` | Body could not be decoded as an image. |
| `501 Not Implemented` | Unsupported transfer encoding, including chunked. |

Error bodies are diagnostic text and are not a stable machine-readable API.
Senders should branch on the HTTP status code.

## Receiver Conformance

A version 1 receiver must demonstrate that it:

1. Accepts an authenticated raw PNG upload.
2. Accepts an authenticated multipart PNG upload.
3. Rejects missing and incorrect credentials.
4. Rejects a token supplied only in the query string.
5. Rejects an empty body, a non-image body, and a body above the limit.
6. Rejects chunked transfer encoding without waiting indefinitely.
7. Handles several sequential uploads without restarting.
8. Saves decoded images using generated local filenames rather than sender
   supplied filesystem paths.

A sender must demonstrate that it:

1. Sends exactly one image per request with `Content-Length`.
2. Places credentials only in the `Authorization` header.
3. Treats every non-2xx response as a failed upload.
4. Does not retry authentication or validation failures indefinitely.
5. Does not log the bearer token.

## macOS Setup Extension

The current macOS receiver additionally exposes:

```text
GET /pair/<pairId>
GET /pair/<pairId>/PhoneSnap.shortcut
```

These routes provide a local setup page and a Shortcut signed by
`/usr/bin/shortcuts`. Other desktop receivers are not required to implement
them, and clients must not use them for capability detection.
