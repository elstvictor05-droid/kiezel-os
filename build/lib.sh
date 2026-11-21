#!/usr/bin/bash
# Shared helpers for build scripts. Source it: . "${CTX}/build/lib.sh"

# cfg <dotted.path> — print a scalar from config.yaml (lists are printed one item per line).
# Uses python3 + PyYAML, which the base image already ships, so no extra package is needed.
cfg() {
    python3 - "${CONFIG}" "$1" <<'PY'
import sys, yaml
node = yaml.safe_load(open(sys.argv[1]))
for part in sys.argv[2].split("."):
    node = node[part]
if isinstance(node, list):
    print("\n".join(str(x) for x in node))
elif isinstance(node, bool):
    print("true" if node else "false")
else:
    print(node)
PY
}
