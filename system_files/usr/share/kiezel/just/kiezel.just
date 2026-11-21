# Kiezel administrator recipes. Run them with: ujust <name>
# Every recipe is a thin wrapper around a script in /usr/libexec/kiezel/ (tested in CI).

# Advanced profile: let your user's podman/distrobox pull from any registry (Flatpak is never affected)
[group('Kiezel: advanced')]
kiezel-containers-open:
    /usr/libexec/kiezel/container-registries open

# Back to the default: only signed Kiezel images
[group('Kiezel: advanced')]
kiezel-containers-close:
    /usr/libexec/kiezel/container-registries close

# Advanced profile: only encrypted DNS to a fixed provider (quad9 or cloudflare); no fallback
[group('Kiezel: advanced')]
kiezel-dns-strict provider="quad9":
    pkexec /usr/libexec/kiezel/dns-mode strict {{ provider }}

# Default DNS: try encryption, fall back to plain DNS when the network does not offer it
[group('Kiezel: advanced')]
kiezel-dns-opportunistic:
    pkexec /usr/libexec/kiezel/dns-mode opportunistic

# Optional: block every USB device that is not plugged in right now
[group('Kiezel: security')]
kiezel-usbguard-enable:
    pkexec /usr/libexec/kiezel/usbguard-mode enable

[group('Kiezel: security')]
kiezel-usbguard-disable:
    pkexec /usr/libexec/kiezel/usbguard-mode disable

# Allow automatic discovery of network printers (opens UDP 5353 for mDNS)
[group('Kiezel: printers')]
kiezel-printer-discovery state="on":
    pkexec /usr/libexec/kiezel/printer-discovery {{ state }}
