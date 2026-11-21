#!/usr/bin/env python3
"""Classify SELinux AVC denials against tests/boot/avc-allowlist.txt (ADR-0010).

Usage: avc-check.py <allowlist> <file-with-avc-lines>

A denial is KNOWN only when every permission in it maps to an allowlisted
(scontext, tcontext, tclass, permission) tuple. Prints:
  UNKNOWN <line>          for each denial that is not fully allowlisted
  STALE <tuple> <link>    for each allowlist entry that matched nothing
  SUMMARY total=N known=K unknown=U stale=S
Exit code 1 if any UNKNOWN denial exists or the allowlist is malformed, else 0.
"""
import re
import sys

AVC = re.compile(
    r"avc:\s+denied\s+\{\s*(?P<perms>[^}]+?)\s*\}.*?"
    r"\bscontext=(?P<s>\S+)\s+tcontext=(?P<t>\S+)\s+tclass=(?P<c>\S+)"
)


def load_allowlist(path):
    entries = {}
    for n, raw in enumerate(open(path), 1):
        line = raw.split("#", 1)[0].strip() if not raw.lstrip().startswith("#") else ""
        if not line:
            continue
        cols = line.split()
        if len(cols) != 5 or not cols[4].startswith("https://"):
            sys.exit(f"allowlist line {n}: need 5 columns ending in one https:// link: {raw.strip()}")
        s, t, c, perm, link = cols
        if "*" in "".join(cols[:4]):
            sys.exit(f"allowlist line {n}: wildcards are not allowed")
        entries[(s, t, c, perm)] = {"link": link, "hits": 0}
    return entries


def main():
    allow = load_allowlist(sys.argv[1])
    total = known = 0
    unknown = []
    for line in open(sys.argv[2], errors="replace"):
        m = AVC.search(line)
        if not m:
            continue
        total += 1
        perms = m.group("perms").split()
        tuples = [(m.group("s"), m.group("t"), m.group("c"), p) for p in perms]
        if all(t in allow for t in tuples):
            known += 1
            for t in tuples:
                allow[t]["hits"] += 1
        else:
            unknown.append(line.strip())
    stale = [(t, e["link"]) for t, e in allow.items() if e["hits"] == 0]
    for line in unknown:
        print(f"UNKNOWN {line}")
    for t, link in stale:
        print(f"STALE {' '.join(t)} {link}")
    print(f"SUMMARY total={total} known={known} unknown={len(unknown)} stale={len(stale)}")
    return 1 if unknown else 0


if __name__ == "__main__":
    sys.exit(main())
