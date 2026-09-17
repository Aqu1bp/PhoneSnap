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
if mode == "tls":
    for name in ("host", "device"):
        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1",
            "-nodes", "-days", "1", "-subj", "/CN=phonesnap-test", "-keyout", str(root / (name + ".key")),
            "-out", str(root / (name + ".pem")),
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
server = socket.socket()
server.bind(("127.0.0.1", 0))
server.listen(1)
print(server.getsockname()[1], flush=True)
try:
    connection, _ = server.accept()
    with connection:
        if mode == "stall":
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
except (OSError, ssl.SSLError):
    pass  # Wrong-pin/cancellation tests deliberately disconnect.
finally:
    server.close()
