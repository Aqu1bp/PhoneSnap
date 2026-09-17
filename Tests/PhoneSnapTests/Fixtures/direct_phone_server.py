"""Local-only transport fixture. Credentials are generated test data, never device keys."""
import plistlib
import socket
import ssl
import subprocess
import struct
import sys
import time
from pathlib import Path

mode, directory = sys.argv[1:]
root = Path(directory)
if mode == "tls" or mode.startswith("lockdown"):
    for name in ("host", "device"):
        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1",
            "-nodes", "-days", "1", "-subj", "/CN=phonesnap-test", "-keyout", str(root / (name + ".key")),
            "-out", str(root / (name + ".pem")),
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
server = socket.socket()
server.settimeout(5)
server.bind(("127.0.0.1", 0))
server.listen(1)
print(server.getsockname()[1], flush=True)


def read_exact(connection, count):
    data = b""
    while len(data) < count:
        chunk = connection.recv(count - len(data))
        if not chunk:
            raise EOFError()
        data += chunk
    return data


def read_plist(connection):
    length = struct.unpack(">I", read_exact(connection, 4))[0]
    return plistlib.loads(read_exact(connection, length))


def write_plist(connection, values):
    data = plistlib.dumps(values)
    connection.sendall(struct.pack(">I", len(data)) + data)


def tls(connection, certificate="device"):
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(root / (certificate + ".pem"), root / (certificate + ".key"))
    return context.wrap_socket(connection, server_side=True)


def lockdown(connection):
    assert read_plist(connection)["Request"] == "StartSession"
    write_plist(connection, {"EnableSessionSSL": mode != "lockdown-plaintext-session"})
    if mode == "lockdown-plaintext-session":
        return
    with tls(connection) as session:
        assert read_plist(session)["Key"] == "UniqueDeviceID"
        write_plist(session, {"Value": "wrong-device" if mode == "lockdown-wrong-id" else "test-device"})
        if mode == "lockdown-wrong-id":
            return
        assert read_plist(session)["Service"] == "com.apple.afc"
        with socket.socket() as photos:
            photos.settimeout(5)
            photos.bind(("127.0.0.1", 0))
            photos.listen(1)
            write_plist(session, {"Port": photos.getsockname()[1], "EnableServiceSSL": mode != "lockdown-plaintext-afc"})
            if mode == "lockdown-plaintext-afc":
                return
            connection, _ = photos.accept()
            connection.settimeout(5)
            with tls(connection, "host" if mode == "lockdown-wrong-afc-cert" else "device") as afc:
                header = read_exact(afc, 40)
                magic, entire, current, sequence, operation = struct.unpack("<8sQQQQ", header)
                assert magic == b"CFA6LPAA" and operation == 3 and entire == current
                assert read_exact(afc, entire - 40) == b"/DCIM\x00"
                body = b".\x00..\x00100APPLE\x00"
                afc.sendall(struct.pack("<8sQQQQ", magic, 40 + len(body), 40 + len(body), sequence, 2) + body)


try:
    connection, _ = server.accept()
    connection.settimeout(5)
    with connection:
        if mode.startswith("lockdown"):
            lockdown(connection)
        elif mode == "stall":
            time.sleep(10)
        elif mode == "truncated":
            connection.sendall(b"short")
        elif mode == "slow-plist":
            # Header and body each arrive within an individual read timeout,
            # but exceed the client's single deadline for the whole exchange.
            header = connection.recv(4, socket.MSG_WAITALL)
            length = struct.unpack(">I", header)[0]
            connection.recv(length, socket.MSG_WAITALL)
            reply = plistlib.dumps({"Value": "late reply"})
            frame = struct.pack(">I", len(reply))
            connection.sendall(frame[:2])
            time.sleep(0.15)
            connection.sendall(frame[2:])
            time.sleep(0.15)
            connection.sendall(reply)
        else:
            if mode == "tls":
                context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
                context.load_cert_chain(root / "device.pem", root / "device.key")
                connection = context.wrap_socket(connection, server_side=True)
            with connection:
                received = b""
                while len(received) < 6:
                    chunk = connection.recv(6 - len(received))
                    if not chunk:
                        break
                    received += chunk
                if received == b"hello!":
                    for part in (b"frag", b"mented", b" reply"):
                        connection.sendall(part)
                        time.sleep(0.005)
except (OSError, ssl.SSLError, EOFError):
    pass  # Wrong-pin/cancellation tests deliberately disconnect.
finally:
    server.close()
