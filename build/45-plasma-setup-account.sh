#!/usr/bin/bash
# Plasma Setup's account page always says "This user will be an administrator", whatever the
# configured groups. On Kiezel it creates the DAILY account without admin rights (ADR-0007), so
# the label and its help text are replaced. The build FAILS if upstream changes the text, so the
# patch is reviewed instead of silently skipped. Upstream: label should follow UserGroups.
set -euo pipefail

qml=/usr/share/plasma/packages/org.kde.plasmasetup.account/contents/ui/main.qml
python3 - "${qml}" <<'PY'
import sys
path = sys.argv[1]
s = open(path).read()
label_old = 'text: i18nc("@info", "This user will be an administrator.")'
label_new = ('text: Qt.locale().name.startsWith("nl") ? "Dit wordt uw dagelijkse account, zonder beheerdersrechten."'
             ' : "This will be your everyday account, without administrator rights."')
help_start = 'toolTipText: xi18nc("@info", "This user will have administrative privileges on the system.'
help_new = ('toolTipText: Qt.locale().name.startsWith("nl") ? "Met deze account kunt u alles doen wat u dagelijks nodig hebt. '
            'Systeeminstellingen veranderen vraagt het wachtwoord van de beheerder, die bij de installatie is aangemaakt."'
            ' : "With this account you can do everything you need every day. Changing system settings asks for the '
            'password of the administrator, who was created during installation."')
if s.count(label_old) != 1:
    sys.exit("plasma-setup account page: administrator label not found exactly once; review the patch")
s = s.replace(label_old, label_new)
lines = s.split("\n")
idx = [i for i, l in enumerate(lines) if l.strip().startswith(help_start)]
if len(idx) != 1:
    sys.exit("plasma-setup account page: administrator help text not found exactly once; review the patch")
indent = lines[idx[0]][: len(lines[idx[0]]) - len(lines[idx[0]].lstrip())]
lines[idx[0]] = indent + help_new
open(path, "w").write("\n".join(lines))
print("plasma-setup account page: daily-account label applied")
PY
