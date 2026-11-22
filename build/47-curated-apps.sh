#!/usr/bin/bash
# Curated apps as Flatpaks from Flathub (ADR-0011, config.yaml "apps"), preinstalled with
# Flatpak's own OS mechanism: /usr/share/flatpak/preinstall.d lists them, and
# kiezel-flatpak-preinstall.service runs "flatpak preinstall" at every boot until all are
# installed. A user who removes one does not get it back (flatpak records the opt-out). A list
# change in a new image is applied at the next boot.
set -euo pipefail
. "${CTX}/build/lib.sh"

# 1. The preinstall list: the default profile's apps (each profile includes the ones above it).
profile="$(cfg profile.default)"
apps=()
for p in simple standard advanced; do
    mapfile -t -O "${#apps[@]}" apps < <(cfg "apps.${p}")
    [[ "${p}" == "${profile}" ]] && break
done
[[ ${#apps[@]} -gt 0 ]] || { echo "no curated apps for profile ${profile}" >&2; exit 1; }
out=/usr/share/flatpak/preinstall.d/kiezel.preinstall
{
    echo "# Generated from config.yaml (profile: ${profile}) by build/47-curated-apps.sh. Flathub only."
    for a in "${apps[@]}"; do
        [[ "${a}" =~ ^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+){2,}$ ]] || { echo "bad app id: ${a}" >&2; exit 1; }
        printf '\n[Flatpak Preinstall %s]\nBranch=stable\nIsRuntime=false\n' "${a}"
    done
} > "${out}"
cat "${out}"
systemctl enable kiezel-flatpak-preinstall.service

# 2. Firefox: the Flatpak replaces the RPM (security updates the same day, ADR-0011). Its
#    enterprise policies ship in /usr and reach the sandbox through the systemconfig extension
#    (tmpfiles.d links /var/lib/flatpak/extension/org.mozilla.firefox.systemconfig to it).
dnf5 -y remove firefox firefox-langpacks
install -Dm0644 "${CTX}/firefox/policies.json" /usr/share/kiezel/firefox-systemconfig/policies/policies.json

# 3. Clear Dutch for the administrator prompt when the daily account installs or removes an app
#    (owner decision 6b): Flatpak's own Dutch text is "Authenticatie is vereist om software te
#    installeren". The build FAILS if upstream changes the message, so the patch is reviewed.
python3 - /usr/share/polkit-1/actions/org.freedesktop.Flatpak.policy <<'PY'
import re, sys
path = sys.argv[1]
s = open(path).read()
new = {
    "org.freedesktop.Flatpak.app-install":
        "Een programma installeren vraagt het wachtwoord van de beheerder. Vraag het aan de persoon die deze computer voor u heeft ingesteld.",
    "org.freedesktop.Flatpak.runtime-install":
        "Een programma installeren vraagt het wachtwoord van de beheerder. Vraag het aan de persoon die deze computer voor u heeft ingesteld.",
    "org.freedesktop.Flatpak.app-uninstall":
        "Een programma verwijderen vraagt het wachtwoord van de beheerder. Vraag het aan de persoon die deze computer voor u heeft ingesteld.",
    "org.freedesktop.Flatpak.runtime-uninstall":
        "Een programma verwijderen vraagt het wachtwoord van de beheerder. Vraag het aan de persoon die deze computer voor u heeft ingesteld.",
}
for action, text in new.items():
    m = re.search(r'<action id="%s">.*?</action>' % re.escape(action), s, re.S)
    if not m:
        sys.exit(f"{action}: action not found; review the patch")
    block = m.group(0)
    msgs = re.findall(r'[ \t]*<message xml:lang="nl">[^<]*</message>\n', block)
    if len(msgs) != 1:
        sys.exit(f"{action}: Dutch message not found exactly once; review the patch")
    indent = re.match(r'[ \t]*', msgs[0]).group(0)
    block2 = block.replace(msgs[0], f'{indent}<message xml:lang="nl">{text}</message>\n')
    s = s.replace(block, block2)
open(path, "w").write(s)
PY
grep -c 'Vraag het aan de persoon' /usr/share/polkit-1/actions/org.freedesktop.Flatpak.policy
