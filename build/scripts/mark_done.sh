#!/bin/bash
# Drop a package from the working dependency graph once its .deb exists:
# remove its own entry, and remove it from every other dependency list.
#
#   mark_done.sh <Package> <graph.json>
#
# Done on the parsed JSON rather than with sed so that package names are
# never treated as regular expressions.
set -euo pipefail

PKGTOMARK="$1"
TARGETFILE="$2"

python3 - "$PKGTOMARK" "$TARGETFILE" <<'EOF'
import json
import sys

pkg, path = sys.argv[1], sys.argv[2]

with open(path) as fh:
    graph = json.load(fh)

# Only drop the entry once its own dependency list is empty.
if not graph.get(pkg):
    graph.pop(pkg, None)

for name, deps in graph.items():
    graph[name] = [dep for dep in deps if dep != pkg]

with open(path, "w") as fh:
    fh.write(json.dumps(graph, indent=4))
EOF
