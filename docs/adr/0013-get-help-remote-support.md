# ADR-0013: "Hulp vragen" (Get help): remote support

- **Status:** Proposed (owner decision needed; see the end)
- **Date:** 2026-11-22
- **Phase:** 3

## Context

Requirement (original brief): a **"Hulp vragen" button** that starts a remote-support session. It
is opt-in, the user gives permission themselves, and the connection is clearly visible. The brief
suggests RustDesk with its own relay, or KDE's own solution, and asks for a motivated choice.

Constraints that matter for the target users:

- The helper is usually **not on the same network** (a son or daughter at home, a volunteer). Both
  ends sit behind home routers (NAT). Nobody can be asked to set up port forwarding.
- Kiezel runs **Wayland**. Screen capture and remote input go through the
  xdg-desktop-portal *RemoteDesktop*/*ScreenCast* portals. Plasma shows its own permission dialog
  and an indicator while the screen is shared. That dialog is the user's consent, and the
  indicator keeps the connection visible.
- The biggest real-world threat is **not** a technical exploit: it is the "helpdesk scam". Someone
  phones, claims to be from the bank or "Microsoft", and talks the person into starting a
  remote-support tool and reading out a code (threat model: social engineering of the daily
  user).

## Options

| | **RustDesk + Kiezel's own relay** | **RustDesk, public relay** | **KDE KRdp (RDP) or krfb (VNC)** | **KRdp over a VPN (WireGuard/Tailscale)** |
|---|---|---|---|---|
| Works across two home routers | Yes (relay) | Yes (relay) | **No** (needs a reachable address) | Yes |
| Encryption | End to end between the two clients, also through the relay | Same | RDP: TLS; krfb/VNC: none on its own | VPN plus RDP TLS |
| Wayland / Plasma 6 | Through the portals (Plasma's own consent dialog). **Must be verified in a VM** | Same | Native (KRdp) | Native |
| Who can connect | **Only clients configured with Kiezel's relay and its public key**: a scammer with the stock app cannot even reach the PC | Anyone with the stock app and the code | n/a | Only VPN members |
| Infrastructure | A small server (hbbs/hbbr) that someone maintains, about €4–6/month | None, but trusts RustDesk's company servers for the relay and ID | None | A VPN account, or our own coordination server; enrolment per PC |
| Effort for the helper | Install RustDesk once, enter the Kiezel server and key once (a printed sheet) | Install RustDesk | n/a | Join the VPN, install an RDP client |
| Packaging | Flathub `com.rustdesk.RustDesk` (fits "apps only from Flathub") | Same | In the image | Extra system service |

## Recommendation

**RustDesk from Flathub, with Kiezel's own relay server, attended sessions only:**

1. The "Hulp vragen" tile (Simple profile) opens a Kiezel page in large text first: *"Alleen
   doen als u zelf uw helper [name from the helper sheet] gebeld hebt. Bank, Microsoft of
   politie vragen dit NOOIT."* Then the buttons [Hulp starten] [Annuleren].
2. [Hulp starten] launches RustDesk in incoming-only mode with the Kiezel relay and key. It shows
   the ID and a **one-time** code in large text, for the user to read out over the phone.
3. When the helper connects, Plasma asks for permission (portal dialog). The screen-sharing
   indicator stays visible. A Kiezel banner "Uw helper kijkt mee — [Stoppen]" stays on top.
4. **No unattended access:** no permanent password, no "start at login". Closing the window or
   [Stoppen] ends the session. The code changes every session.
5. **Scam barrier:** the relay only accepts clients that carry Kiezel's public key, so the stock
   RustDesk app that a scammer uses cannot reach the PC at all. This is the main reason to run our
   own relay instead of the public one.
6. The relay server runs the official RustDesk server (open source, AGPL). It only passes
   encrypted traffic and stores no screen content. Its key pair is generated on the server and
   never in the repository.

Why not the KDE tools: KRdp and krfb are good for a local network, but neither works across two
home routers without port forwarding or a VPN. A VPN asks too much of the helper and adds
infrastructure for every PC.

## To verify before implementing (in a VM, then on the old PC)

- RustDesk's Flatpak on Plasma 6 Wayland: the portal consent dialog appears, the remote mouse
  and keyboard work, and the session ends when the window closes.
- RustDesk accepts a preset relay and key through its configuration file, without the user
  typing anything. The page sets them; the user sees only the code.
- Behaviour when the relay is unreachable: a clear Dutch message, no fallback to public servers.

## Owner decision needed

1. **Relay server:** who hosts and maintains it (cost about €4–6/month, plus updates), or start
   with the public RustDesk relay and accept the weaker scam barrier until a server exists?
2. **The helper's side:** OK that the helper installs RustDesk once and enters the Kiezel
   server and key from a printed sheet (added to the helper sheet)?
3. **Who may help:** only the helper named on the helper sheet (shown on the warning page), or
   anyone the user calls?
