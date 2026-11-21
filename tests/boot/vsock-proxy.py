#!/usr/bin/env python3
"""SSH ProxyCommand over virtio-vsock: vsock-proxy.py <guest-cid> <port>

The boot test talks to the VM over AF_VSOCK instead of the virtual network, so the Kiezel
firewall (which rejects incoming SSH on the network, as it must) stays fully enabled during
tests. systemd-ssh-generator binds sshd to vsock port 22 automatically inside a VM.
"""
import os
import selectors
import socket
import sys

cid, port = int(sys.argv[1]), int(sys.argv[2])
sock = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
sock.connect((cid, port))

sel = selectors.DefaultSelector()
sel.register(sys.stdin.buffer, selectors.EVENT_READ, "in")
sel.register(sock, selectors.EVENT_READ, "sock")
while True:
    for key, _ in sel.select():
        if key.data == "in":
            data = os.read(sys.stdin.fileno(), 65536)
            if not data:
                sock.shutdown(socket.SHUT_WR)
                sel.unregister(sys.stdin.buffer)
                continue
            sock.sendall(data)
        else:
            data = sock.recv(65536)
            if not data:
                sys.exit(0)
            os.write(sys.stdout.fileno(), data)
