# Architecture

> Phase 0 draft. Filled in as the phases land.

Kiezel is a **bootable container image**. The whole operating system (kernel, systemd, KDE
Plasma, configuration) is built like a container in CI, signed, and pulled by installed
machines as one atomic unit. Applications are Flatpaks from Flathub and live outside the image.

## Build and update pipeline

```mermaid
flowchart LR
  subgraph upstream["Upstream"]
    F["Fedora Kinoite<br/>(Fedora Atomic SIG)"] --> U["ghcr.io/ublue-os/kinoite-main<br/>signed by Universal Blue"]
  end

  subgraph repo["kiezel-os repository"]
    C["config.yaml<br/>(schema-validated)"]
    CF["Containerfile<br/>FROM kinoite-main:45@sha256"]
    S["build/ + system_files/<br/>policy.json, hardening, profiles"]
    R["Renovate<br/>digest bumps"] -.PR.-> CF
  end

  subgraph ci["GitHub Actions"]
    V1["verify Universal Blue<br/>signature"] --> B["podman build<br/>bootc container lint"]
    B --> T["boot test in QEMU<br/>Secure Boot, AVC=0,<br/>greenboot, signed origin"]
    T --> SG["cosign sign<br/>(primary key)"]
    SG --> P["push ghcr.io/…/kiezel:stable"]
    P --> ISO["mkksiso netinstall ISO<br/>SHA256SUMS + cosign sign-blob"]
  end

  U --> V1
  C --> B
  CF --> B
  S --> B
  ISO --> GR["GitHub Release"]

  subgraph device["Installed device"]
    RO["rpm-ostreed-automatic<br/>(stage, not on metered)"] -->|"pull + verify against<br/>policy.json (kiezel keys)"| P
    RO --> ST["staged deployment"]
    ST -->|"next reboot"| GB{"greenboot<br/>health checks"}
    GB -->|healthy| OK["new version active"]
    GB -->|"fails 3×"| RB["bootc rollback<br/>to previous deployment"]
  end
```

## Trust chain

1. Fedora signs RPMs and its base image. Universal Blue signs `kinoite-main` with cosign.
2. CI checks Universal Blue's signature **before** building on top of it.
3. CI signs the Kiezel image with Kiezel's primary key; the signature is logged in Rekor.
4. Devices accept only images from `ghcr.io/elstvictor05-droid/kiezel` signed with Kiezel's
   primary or backup key (ADR-0003, ADR-0004).
5. The installer ISO is Fedora's Secure-Boot-signed netinstall image. Our kickstart makes the
   install-time pull verify against Kiezel's key too (ADR-0005).

## Decisions

See [`docs/adr/`](adr/).
