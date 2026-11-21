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

# Default DNS: Quad9 (encrypted when possible); the router for local names and as automatic fallback
[group('Kiezel: privacy')]
kiezel-dns-quad9:
    pkexec /usr/libexec/kiezel/dns-mode quad9

# Privacy choice "off": use only the network's (router's) DNS, as without Kiezel
[group('Kiezel: privacy')]
kiezel-dns-router:
    pkexec /usr/libexec/kiezel/dns-mode router

# Advanced profile: only encrypted DNS to a fixed provider (quad9 or cloudflare); no fallback
[group('Kiezel: advanced')]
kiezel-dns-strict provider="quad9":
    pkexec /usr/libexec/kiezel/dns-mode strict {{ provider }}

# Optional: block every USB device that is not plugged in right now
[group('Kiezel: security')]
kiezel-usbguard-enable:
    pkexec /usr/libexec/kiezel/usbguard-mode enable

[group('Kiezel: security')]
kiezel-usbguard-disable:
    pkexec /usr/libexec/kiezel/usbguard-mode disable

# Find network printers automatically on THIS home network (mDNS in zone kiezel-home); "off" to undo
[group('Kiezel: printers')]
kiezel-printer-discovery state="on":
    pkexec /usr/libexec/kiezel/printer-discovery {{ state }}
