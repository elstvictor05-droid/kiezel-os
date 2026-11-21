# Testing Kiezel

Every phase is tested on a VM that looks like the target hardware: **4 GB RAM, 2 vCPUs, UEFI
with Secure Boot (Microsoft keys enrolled, so Fedora's shim must be accepted) and a TPM2**.

## What CI tests automatically

| Workflow | When | What |
|---|---|---|
| `validate` | every push and PR | `config.yaml` against its schema, shellcheck |
| `build` → `build + boot test` | every PR, main, weekly | Base signature check, image build, `bootc container lint`, static image checks, kickstart guard, then a QEMU boot with Secure Boot and swtpm. The boot checks: system `running`, Secure Boot on, SELinux enforcing, **0 AVC denials**, greenboot healthy, TPM2 present, origin is `ghcr.io/…/kiezel:stable`, a signed canary is accepted, an **unsigned** canary and an **unsigned bootable image are refused**, and a **deliberately broken image rolls back by itself**. |
| `build` → `sign + promote` | main, after owner approval | Signs the tested digest, tags `:stable` and `:YYYYMMDD`, publishes the signature canaries |

The boot-test report and serial log are attached to every run as the `boot-test-report`
artifact.

## Local testing (QEMU/KVM)

Requirements on the host: `podman qemu-system-x86 ovmf swtpm`, and your user in group `kvm`.

```bash
# 1. Build the image (rootless works)
podman build -t localhost/kiezel:dev .

# 2. Static checks
podman run --rm -v ./tests/image:/t:ro,z localhost/kiezel:dev /t/check-image.sh

# 3. Test disk + boot test (bootc-image-builder needs root)
ssh-keygen -t ed25519 -N '' -f tests/out/ci_key
podman save localhost/kiezel:dev | sudo podman load           # copy into root storage
sudo tests/boot/make-test-disk.sh localhost/kiezel:dev tests/out/ci_key.pub tests/out/disk
tests/boot/boot-test.sh --disk tests/out/disk/disk.qcow2 --key tests/out/ci_key

# 4. Installer ISO (rootless) and install test
iso/build-iso.sh --test --test-pubkey tests/out/ci_key.pub tests/out/iso
tests/iso/install-test.sh --iso tests/out/iso/kiezel-netinstall-ci-test.iso --expect success
```

For a graphical session, drop `-display none` from the scripts' QEMU line, or connect with
`virt-viewer` to a libvirt VM created with:

```bash
virt-install --name kiezel --memory 4096 --vcpus 2 --cpu host-passthrough \
  --boot uefi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=yes,firmware.feature1.name=enrolled-keys,firmware.feature1.enabled=yes \
  --tpm backend.type=emulator,backend.version=2.0,model=tpm-crb \
  --cdrom kiezel-netinstall.iso --disk size=40 --osinfo fedora-unknown
```

## Proxmox VE

1. **Upload the ISO:** Datacenter → *storage* → ISO Images → Upload `kiezel-netinstall.iso`.
2. **Create VM:**
   - *OS:* the ISO; type Linux 6.x.
   - *System:* Machine **q35**, BIOS **OVMF (UEFI)**, add an **EFI disk** with
     **Pre-Enroll keys** ticked (Microsoft keys, needed for Secure Boot with Fedora's shim).
     Tick **Add TPM** with version **v2.0**.
   - *Disks:* VirtIO SCSI single, 40 GB.
   - *CPU:* 2 cores, type `host` (or `x86-64-v2-AES` for a portable VM).
   - *Memory:* **4096 MB**, ballooning off (gives accurate RAM measurements).
   - *Network:* VirtIO, on a bridge with DHCP and internet access, because the installer
     downloads the image.
3. **Start and install.** Follow [the user guide](user-guide/installing.md).
4. **Check after the first login** (as the admin, in Konsole):
   ```bash
   mokutil --sb-state                 # SecureBoot enabled
   getenforce                         # Enforcing
   bootc status                       # booted: ghcr.io/elstvictor05-droid/kiezel:stable
   systemd-cryptenroll /dev/disk/by-partlabel/root 2>/dev/null || lsblk -f   # LUKS2 present
   journalctl -b -o cat | grep -c 'avc:  denied'   # 0
   ```
5. **Without TPM:** remove the TPM device from the VM. The disk must then ask for the
   passphrase instead of unlocking by itself.
