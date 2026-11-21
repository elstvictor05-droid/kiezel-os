# Installing Kiezel

> Draft (Phase 1). Large screenshots are added in Phase 4 once the installer screens are final.
> Placeholders are marked **[screenshot]**.

## Before you start

You need:

- A computer with a 64-bit processor and at least 4 GB of memory.
- A USB stick of at least 2 GB. Everything on it will be erased.
- **An internet connection during the installation.** The installer downloads Kiezel while it
  installs. A network cable is easiest. Wi-Fi also works; see step 3.
- About 30 to 60 minutes.

> ⚠️ **The installer erases the whole disk of the computer.** Copy your photos and documents
> to another place first.

## Step 1: Download and check the installer

1. Download `kiezel-netinstall.iso` and `SHA256SUMS` from the
   [latest release](https://github.com/elstvictor05-droid/kiezel-os/releases/latest).
2. Optional, for technical helpers: check that the file is genuine.

   ```
   sha256sum -c SHA256SUMS
   cosign verify-blob --key cosign.pub --bundle kiezel-netinstall.iso.sigstore.json kiezel-netinstall.iso
   ```

## Step 2: Put it on a USB stick and start from it

1. Use [Fedora Media Writer](https://fedoraproject.org/workstation/download) or
   [balenaEtcher](https://etcher.balena.io/) to write the ISO to the USB stick.
2. Put the stick in the computer, switch it on, and press the boot-menu key. This is often
   **F12**, **F11**, **Esc** or **F8**, depending on the brand. Choose the USB stick.
3. Choose **Install Kiezel**. **[screenshot]**

## Step 3: Connect to the internet

**With a network cable:** nothing to do. The installer connects by itself.

**With Wi-Fi:**

1. On the main screen of the installer, click **Network & Host Name**. **[screenshot]**
2. Click the Wi-Fi line in the list on the left. **[screenshot]**
3. Click **Select network** (top right) and choose your network by name. **[screenshot]**
4. Type the Wi-Fi password and click **Connect**. You can usually find the password on a
   sticker on your internet box.
5. Wait until it says **Connected**. Then click **Done** (top left).

If the network does not appear, move the computer closer to the internet box and click
**Refresh**.

## Step 4: Choose a passphrase for the disk

Kiezel locks (encrypts) everything on the disk. If the computer is lost or stolen, nobody can
read your files without this passphrase.

1. The installer asks for a **passphrase**. Choose a sentence you will remember, for example
   four unrelated words: `garden bicycle orange piano`.
2. **Write it down on paper and keep it at home in a safe place.** If you forget it, your files
   cannot be recovered. Nobody can unlock them, not even a technician.

On computers with a security chip (TPM2), Kiezel will unlock the disk by itself after the first
start, so you will rarely need the passphrase. Keep the paper anyway.

## Step 5: Create the administrator account

This account is for installing updates and changing settings. Give it to the person who helps
you with the computer, or keep it on the same paper as the passphrase.

1. Click **User Creation**. **[screenshot]**
2. Fill in a name, for example `beheerder` (Dutch for administrator), and a password.
3. Leave **Make this user administrator** switched on, then click **Done**.

## Step 6: Install

Click **Begin Installation**. The computer downloads and installs Kiezel. When it is finished,
it restarts. Remove the USB stick.

## Step 7: First start

At first start, Kiezel asks for your language, Wi-Fi and **your own everyday account**. That is
the account you use every day. It cannot accidentally break the system. See
[First start](first-start.md) (Phase 3).
