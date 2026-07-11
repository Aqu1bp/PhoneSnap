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
- The maximum complete request body is 33,554,432 bytes (32 MiB).
- A sender must not follow redirects when uploading credentials and image data.

Version 1 uses plain HTTP because the generated iOS Shortcut cannot establish a
pinned trust relationship with an ephemeral local certificate. The bearer
credential is therefore observable by other parties that can inspect LAN
traffic. Users must use wired capture instead on untrusted networks.

## Pairing Material

A receiver provisions:

- `pairId`: an unguessable, opaque, case-sensitive URL capability identifying
  a pairing.
- `token`: an opaque, case-sensitive, high-entropy bearer credential
  authorizing uploads.

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

The only accepted credential location is the `Authorization` header. The
`Bearer` authentication scheme is case-insensitive; the token is not. Senders
must not place a token in the URL, query string, filename, or other headers.

Receivers accept either:

1. A raw PNG body with `Content-Type: image/png`.
2. `multipart/form-data` containing one PNG part named `file`, with an
   `image/png` part content type and a filename.

Receivers may additionally accept other decodable `image/*` formats. Senders
cannot assume JPEG, HEIC, or other optional formats are portable.

A receiver must decode the content as an image before treating the request as
successful. PhoneSnap normalizes accepted input to PNG before saving it.

Version 1 defines no metadata headers. Receivers must ignore unknown headers,
and senders must not depend on unknown headers being stored or interpreted.

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

Every request is independent. Version 1 provides no ordering guarantee across
concurrent requests and no deduplication guarantee across receiver restarts.

## Error Responses

| Status | Meaning |
| --- | --- |
| `400 Bad Request` | Malformed/incomplete request or empty upload body. |
| `401 Unauthorized` | Missing or invalid bearer credential. |
| `408 Request Timeout` | Request did not complete within the receiver deadline. |
| `404 Not Found` | Unknown route or pair ID. |
| `405 Method Not Allowed` | Upload route used with a method other than `POST`. |
| `411 Length Required` | Authenticated upload omitted `Content-Length`. |
| `413 Payload Too Large` | Declared body exceeds 32 MiB. |
| `415 Unsupported Media Type` | Body could not be decoded as an image. |
| `417 Expectation Failed` | Unsupported `Expect` header. |
| `431 Request Header Fields Too Large` | Header block exceeds the receiver limit. |
| `500 Internal Server Error` | Receiver accepted an image but could not store it. |
| `501 Not Implemented` | Unsupported transfer encoding, including chunked. |

Error bodies are diagnostic text and are not a stable machine-readable API.
Senders should branch on the HTTP status code.

## Receiver Conformance

A version 1 receiver must demonstrate that it:

1. Accepts an authenticated raw `image/png` upload.
2. Accepts an authenticated multipart PNG in a `file` part.
3. Rejects missing and incorrect credentials.
4. Rejects a token supplied only in the query string.
5. Rejects an empty body, a non-image body, and a body above the limit.
6. Rejects missing, malformed, negative, duplicate, and oversized
   `Content-Length` values before buffering a body.
7. Rejects chunked transfer encoding without waiting indefinitely and either
   supports `Expect: 100-continue` or returns `417`.
8. Authenticates an upload before buffering its body.
9. Limits simultaneous and incomplete requests.
10. Handles several sequential uploads without restarting.
11. Saves decoded images using generated local filenames rather than sender
   supplied filesystem paths.

A sender must demonstrate that it:

1. Sends exactly one PNG per request with a decimal `Content-Length`.
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
