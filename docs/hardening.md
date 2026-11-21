# Hardening

Every measure lists **what** it does, **why**, the **risk** (what could break), and **how it is
tested**. Selection rule (owner, Phase 2): nothing that breaks Flatpak, Firefox or old GPUs.
Explicitly excluded: `init_on_free` (too slow on old PCs) and user-namespace restrictions
(Flatpak and the Firefox sandbox need them).

"Boot test" means `tests/boot/boot-test.sh`, which runs on every PR with Secure Boot, a TPM2 and
the firewall enabled. SSH goes over virtio-vsock, so tests never need an open network port.

## 1. Updates and integrity

| Measure | What | Why | Risk | Tested |
|---|---|---|---|---|
| Signed images only | `policy.json` requires a sigstore signature from Kiezel's key for `ghcr.io/elstvictor05-droid/kiezel` (ADR-0003/0004) | Nobody can push an OS update without the key **and** registry write access | Losing every key stops updates (offline backup key, ADR-0003) | Boot test: signed accepted, unsigned and wrong-key rejected; installer refuses unsigned |
| Installer verifies too | Kickstart `%pre` installs a reject-by-default policy in the installer (ADR-0005) | Fedora's installer otherwise accepts any image | None found | `iso.yml`: install refused for an unsigned image |
| Automatic rollback | greenboot required checks: login screen, network, SELinux enforcing, trust policy (ADR-0008) | A broken update cannot lock the user out | A false failure would roll back a good update (#219 is tested) | Boot test: broken image rolls back by itself, no false rollback on power-off |
| No rollback loop | Failed digests are skipped by the update gate | The broken image is never staged again | A transiently failed digest waits for the next image | Boot test: 2 timer runs after rollback stage nothing |
| No surprise reboots | `bootc-fetch-apply-updates.timer` masked; updates are staged and applied on the next normal restart | Users are never interrupted | Updates wait for a restart | Image check |
| Firmware updates | `fwupd-refresh.timer` enabled (LVFS metadata). Installing stays a visible user/admin action | Old PCs often have firmware security fixes | A bad vendor update; LVFS and the vendor sign updates | Boot test: timer enabled |

## 2. Container trust: other registries (ADR-0004)

| Profile | Images from other registries (docker.io, quay.io, …) | podman / distrobox / toolbox |
|---|---|---|
| **Simple** | **Rejected** (catch-all `reject`) | Do not work. Not offered in this profile anyway |
| **Standard** | **Rejected** (catch-all `reject`) | **Do not work.** Pulling any image is refused. This is the known cost of this profile |
| **Advanced** | Allowed **per user** after `ujust kiezel-containers-open` | Work for that user |

- **Flatpak is never affected.** Flatpak does not use `containers/policy.json`. It has its own
  OSTree/OCI signature checking against Flathub, so apps install and update the same way in
  every profile.
- **Why per-user:** the Advanced opt-in writes `~/.config/containers/policy.json` for that
  user only. The system policy that bootc uses for OS updates stays exactly as shipped, so a key
  rotation in a future image still applies. An edited `/etc` file would stop receiving updates
  through the 3-way merge.
- **Risk:** an Advanced user can run untrusted container images. That runs as that user, not as
  root, and does not touch OS updates.
- **Tested:** the boot test checks that root is rejected from quay.io, that the opt-in user can
  pull, and that the system policy hash is unchanged.

## 3. Network

| Measure | What | Why | Risk | Tested |
|---|---|---|---|---|
| Firewall zone `kiezel` | Default zone with target REJECT; only `dhcpv6-client`. Replaces Fedora's `FedoraWorkstation`, which accepts **all incoming TCP/UDP 1025–65535** plus ssh and samba-client | No service on this PC can be reached from the network, even one started by mistake | Peer-to-peer apps that need incoming ports (some games, LAN file sharing) do not work. Printer auto-discovery: see below | Boot test: listener on :8080 answers inside the VM (200) but is unreachable from outside |
| DHCPv6 exception | `dhcpv6-client` (UDP 546) stays allowed | Needed to get an IPv6 address on DHCPv6 networks | Minimal: only the DHCPv6 client port | Zone file check |
| Printer discovery (mDNS) | **Off** by default. `ujust kiezel-printer-discovery on` opens UDP 5353 | Rule: no open incoming ports | Network printers are not found automatically; adding them by address still works. **Accessibility trade-off, owner decision pending** | Recipe script tested by hand; CI test in Phase 3 |
| sshd off | `sshd.service` not enabled | No remote login surface | Remote help uses an explicit opt-in tool (Phase 3) | Boot test: inactive |
| SSH over vsock (VMs only) | systemd-ssh-generator binds sshd to AF_VSOCK **inside a VM that has a vsock device** | systemd default; only the hypervisor host can reach it, and it already has full control over the VM | None on real hardware (no vsock) | Used by the tests |
| ICMP redirects ignored | `accept_redirects=0`, `secure_redirects=0`, `send_redirects=0` | A hostile Wi-Fi cannot reroute traffic with forged redirects | None for a desktop (not a router) | Boot test: sysctl values |

### DNS-over-TLS: opportunistic by default, strict in Advanced

| Mode | Behaviour | Protects against | Weakness |
|---|---|---|---|
| **opportunistic** (default) | systemd-resolved tries TLS (port 853) with the network's DNS server and falls back to plain DNS if it does not answer | Passive eavesdropping **when** the DNS server supports DoT | **Downgrade attack:** a network that blocks port 853 (or a hostile hotspot that drops it) silently forces plain DNS. Most home routers and ISP resolvers do not offer DoT, so on many networks this is effectively plain DNS |
| **strict** (Advanced: `ujust kiezel-dns-strict quad9\|cloudflare`) | Only encrypted DNS to a named provider, no fallback | Eavesdropping **and** downgrade | DNS (and so the internet) **stops working** on networks that block port 853: some hotels, schools, captive portals. It also sends every DNS query to that provider |

Why this default: for the target users, "the internet stops working in the hotel" is worse
than a downgrade on hostile networks. HTTPS-only in Firefox still protects the content of
connections. Strict mode is one command for users and helpers who want it. **Open question
for the owner:** should Kiezel set a default DoT-capable provider in opportunistic mode? That
would make the encryption real on most networks, at the cost of sending DNS to a third party.

## 4. Kernel (sysctl `/usr/lib/sysctl.d/60-kiezel-hardening.conf`)

Already enforced by Fedora's kernel config and therefore not repeated: `dmesg_restrict`,
unprivileged BPF off by default, `init_on_alloc`, randomised kernel stack offset, randomised
slab freelists.

| Setting | What | Why | Risk |
|---|---|---|---|
| `kernel.kptr_restrict=2` | Kernel addresses hidden from everyone | Makes kernel exploits harder to write | `perf`/tracing tools show zeros (developer-only) |
| `kernel.yama.ptrace_scope=1` | Only a parent may trace its child | One process of the user cannot read another's memory (e.g. a browser's) | `gdb -p <pid>` needs root (developer-only) |
| `kernel.kexec_load_disabled=1` | No loading another kernel at runtime | Closes a Secure Boot bypass route | kdump crash capture is not available |
| `kernel.unprivileged_bpf_disabled=1` | BPF for root only, and cannot be re-enabled without a reboot | BPF is a frequent local privilege-escalation surface | None for desktop apps |
| `net.core.bpf_jit_harden=2` | Constant blinding in the BPF JIT | JIT spraying | Tiny CPU cost for BPF (firewall rules) |
| `dev.tty.ldisc_autoload=0` | No automatic loading of TTY line disciplines | Several past local root bugs | Exotic serial hardware needs a manual `modprobe` |
| `fs.suid_dumpable=0` | No core dumps of setuid programs | Dumps could contain password hashes | None |
| `fs.protected_fifos=2`, `fs.protected_regular=2` | Stricter rules for files in shared sticky directories such as /tmp | Classic /tmp attacks | Badly written scripts sharing /tmp files between users |
| `vm.mmap_rnd_bits=32`, `vm.mmap_rnd_compat_bits=16` | Maximum address-space randomisation | ASLR brute force | Slightly more address-space fragmentation; irrelevant at 4–8 GB |

**Tested:** the boot test reads every line of this file and checks the running value with
`sysctl -n`.

## 4b. Blocked kernel modules (`/usr/lib/modprobe.d/60-kiezel-blacklist.conf`)

| Modules | Why | Risk | Tested |
|---|---|---|---|
| `dccp`, `sctp`, `rds`, `tipc` | Rare network protocols with a history of exploitable bugs. Nothing on a home desktop uses them (WebRTC does SCTP in user space) | Specialist software (telecom, clustering) needs them | Boot test: `modprobe` fails, none loaded |
| `firewire-core`, `firewire-ohci`, `firewire-sbp2` | FireWire devices get direct memory access, so a plugged-in device can read RAM (DMA attack). Many old PCs still have a FireWire port | Old FireWire camcorders and audio interfaces do not work | Same |

## 5. Boot parameters (`/usr/lib/bootc/kargs.d/10-kiezel-hardening.toml`)

| Parameter | What | Why | Risk |
|---|---|---|---|
| `slab_nomerge` | Kernel object caches are not merged | Heap overflows cannot reach unrelated objects as easily | A few MB more kernel memory |
| `page_alloc.shuffle=1` | Randomised free page lists | Harder to predict memory layout; activates code already built into Fedora's kernel | Negligible |
| `vsyscall=none` | No legacy fixed-address vsyscall page | Removes a fixed address that exploits use | Ancient static 64-bit binaries (pre-2013 glibc) crash. Flatpak runtimes and Fedora apps are unaffected |
| `debugfs=off` | No kernel debug filesystem | debugfs leaks kernel internals | Some diagnostic tools (e.g. parts of powertop) lose data |

Not chosen: `init_on_free=1` (owner: speed on old PCs), `nosmt` (halves the CPU on old
dual-cores), `mitigations=auto,nosmt`, `lockdown=confidentiality` (breaks hibernation), and
module signature enforcement beyond what Secure Boot lockdown already does.

**Tested:** the boot test checks `/proc/cmdline` for every parameter on the installed test
disk. On real old hardware, GPU and suspend are checked on the test PC (v0.1 blocker).

## 6. Browser (Firefox enterprise policies)

File: `firefox/policies.json`, installed to `/usr/lib64/firefox/distribution/policies.json`.

| Policy | Why | Risk |
|---|---|---|
| uBlock Origin force-installed | Ads are a main source of scams and malware for older users | A few sites detect blockers and nag |
| `HttpsOnlyMode: force_enabled` | No silent plain-HTTP connections | Old HTTP-only sites show a warning page first |
| `DisableTelemetry`, `DisableFirefoxStudies` | Privacy | None |
| `PrimaryPassword: true` | Saved passwords are only stored behind a primary password | The user must set and remember one more password, so the helper should set it up |
| Tracking protection plus cookie partitioning | Privacy | Rare login problems on old single sign-on sites; standard ETP level, **not** "strict" |

**Tested:** the boot test starts Firefox headless with a fresh profile and checks that the
policy installed uBlock Origin. That also exercises the content sandbox under the kernel
hardening.

**Open decision:** Firefox currently ships as the RPM in the base image, while the requirement
says apps come only from Flathub. See ADR-0011.

## 7. Optional: USBGuard

Installed but **off**. `ujust kiezel-usbguard-enable` allows exactly the devices plugged in at
that moment and blocks every new USB device.

- **Risk:** a new keyboard, mouse or USB stick does not work until an admin allows it, which is
  hard for older users. That is why it stays off by default.
- **Tested:** the boot test checks it is inactive by default.

## 8. Security audit score

Lynis (pinned 3.1.7, SHA-256 checked) runs in every boot test. The hardening index is printed
in the report and the full `lynis-report.dat` is a CI artifact. The score is tracked, not gated:
Lynis also flags things that do not apply to an image-based desktop (for example separate
partitions for /var/tmp).

### Lynis findings that do not apply

- **AUTH-9216, "grpck found errors":** on ostree/bootc systems the system groups live in
  `/usr/lib/group` (nss-altfiles), and `/etc/group` only holds local additions. `grpck` does not
  know this layout. This is a false positive, not corruption.
- Suggestions such as separate partitions, a legal banner, process accounting, a malware
  scanner and remote logging do not fit a single-user, image-based home desktop. They are not
  adopted.

## 9. Known upstream exceptions

### `bootupd_t` is a permissive SELinux domain

Fedora's policy ships `bootupd_t` (bootloader updates) as **permissive**: its accesses are
logged, not enforced. On installed systems it reads two install-time files with wrong labels
(`/boot/bootupd-state.json` is `unlabeled_t`, `/sysroot/.bootc-aleph.json` is `default_t`).

| | |
|---|---|
| **What it means** | A compromised or buggy `bootupctl`, running as root during bootloader updates, is not confined by SELinux |
| **Why accepted** | Fedora's policy decision. Making it enforcing ourselves risks broken bootloader updates. Kiezel changes no SELinux policy without its own ADR |
| **Mitigation** | `bootupctl` only comes from our signed image. The denials are allowlisted by exact tuple (ADR-0010) and flagged when they disappear |
| **Upstream** | https://github.com/sparewall/sparewall/issues/111 |

### tuned's relabel probe

`tuned` runs `bootc`, which deliberately tries an invalid relabel to test its rights. The denial
(`mac_admin` in `tuned_t`) is the intended "no". Upstream:
https://github.com/redhat-performance/tuned/issues/895

## Gate wording

CI enforces **"0 unexpected AVC denials"**. Every denial must be a listed upstream tuple
(ADR-0010); any other denial fails.
