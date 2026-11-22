#!/usr/bin/bash
# Every curated app in config.yaml (all profiles) must exist on Flathub and must NOT be
# end-of-life. Flathub renames apps now and then (org.mozilla.Thunderbird became
# org.mozilla.thunderbird_esr); "flatpak preinstall" then silently installs the replacement and
# config.yaml no longer says what users get. Runs in the build (inside the image) and weekly
# (iso.yml), because an app can go end-of-life without any change in this repository.
#
# Usage: check-flathub-eol.sh [config.yaml]     (FLATPAK_INSTALLATION=--system | --user)
# Exit:  0 all fine | 1 end-of-life or not on Flathub | 3 Flathub unreachable after retries
set -uo pipefail

config="${1:-/config.yaml}"
inst="${FLATPAK_INSTALLATION:---system}"
mapfile -t apps < <(python3 -c '
import sys, yaml
c = yaml.safe_load(open(sys.argv[1]))
seen = []
for p in ("simple", "standard", "advanced"):
    for a in c["apps"].get(p) or []:
        if a not in seen: seen.append(a)
print("\n".join(seen))' "${config}") || { echo "FAIL  cannot read the app list from ${config}"; exit 1; }
[[ ${#apps[@]} -gt 0 ]] || { echo "FAIL  no curated apps in ${config}"; exit 1; }

# 1. Is Flathub reachable at all? "flatpak remote-info" reports a network failure as "No such
#    ref", so first load the remote's app list (retries); only then is "No such ref" an answer.
reach="" ok=0
for attempt in 1 2 3; do
    reach="$(LC_ALL=C flatpak remote-ls "${inst}" flathub --app --columns=application 2>&1)"
    if ! grep -q '^error' <<<"${reach}" && [[ "$(wc -l <<<"${reach}")" -gt 100 ]]; then ok=1; break; fi
    sleep $((attempt * 10))
done
if [[ ${ok} -eq 0 ]]; then
    echo "FAIL  Flathub UNREACHABLE after 3 attempts (network problem, NOT an end-of-life finding): $(grep -m1 '^error' <<<"${reach}" || tail -1 <<<"${reach}")"
    exit 3
fi

# 2. Per app: remote-info shows "End-of-life" / "End-of-life-rebase" for retired apps (which
#    remote-ls hides), and "No such ref" for ids that do not exist.
rc=0
for a in "${apps[@]}"; do
    out="" ok=0
    for attempt in 1 2 3; do
        out="$(LC_ALL=C flatpak remote-info "${inst}" flathub "app/${a}/x86_64/stable" 2>&1)" && { ok=1; break; }
        grep -q 'No such ref' <<<"${out}" && break
        sleep $((attempt * 10))
    done
    if [[ ${ok} -eq 1 ]]; then
        eol="$(sed -nE 's/^ *End-of-life: *(.*)$/\1/p' <<<"${out}")"
        rebase="$(sed -nE 's/^ *End-of-life-rebase: *(.*)$/\1/p' <<<"${out}")"
        if [[ -n "${eol}${rebase}" ]]; then
            echo "FAIL  ${a} is END-OF-LIFE on Flathub: ${eol:-?}${rebase:+ (replaced by ${rebase})}. Update config.yaml."
            rc=1
        else
            echo "PASS  ${a} is on Flathub and not end-of-life"
        fi
    elif grep -q 'No such ref' <<<"${out}"; then
        echo "FAIL  ${a} does not exist on Flathub (app/${a}/x86_64/stable). Check the id in config.yaml."
        rc=1
    else
        echo "FAIL  Flathub UNREACHABLE for ${a} after 3 attempts (network problem, NOT an end-of-life finding): $(tail -1 <<<"${out}")"
        [[ ${rc} -eq 0 ]] && rc=3
    fi
done
exit "${rc}"
