# system_files/

Copied onto `/` of the image at build time (`etc/`, `usr/`). Holds the trust policy
(ADR-0004), hardening config, greenboot checks and `/etc/skel`.
Only **public** keys (`*.pub`) belong here; `.gitignore` blocks private keys.
