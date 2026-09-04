#!/usr/bin/env bash
# The same Acme workspace, assembled the way large multi-repo trees usually are:
# with Google `repo` and a manifest.
#
# The point of this demo is the division of labour. A manifest says how the tree
# is checked out; it never says what a change propagates to. deck imports the
# first for you and refuses to invent the second.
#
#   ./demo-repo.sh            run the tour
#   ./demo-repo.sh --keep     leave the workspace on disk
set -euo pipefail

PACK="$(cd "$(dirname "${BASH_SOURCE[0]}")/pack" && pwd)"
KEEP="${1:-}"

if [ -n "${DECK_BIN:-}" ]; then
  DECK="$DECK_BIN"
elif command -v deck >/dev/null; then
  DECK="$(command -v deck)"
elif [ -x "$(dirname "$PACK")/../deck/plugins/deck/bin/deck" ]; then
  DECK="$(cd "$(dirname "$PACK")/../deck" && pwd)/plugins/deck/bin/deck"
else
  echo "deck not found. Set DECK_BIN, or clone github.com/devfilipe/deck next to this one." >&2
  exit 1
fi

WS="$(mktemp -d)"
[ "$KEEP" = "--keep" ] || trap 'rm -rf "$WS"' EXIT

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
run() { printf '\n\033[2m$ deck %s\033[0m\n' "$*"; "$DECK" "$@"; }

# ------------------------------------------------- a repo-assembled workspace
: > "$WS/.acme-root"
echo '{ "name": "acme" }' > "$WS/package.json"
mkdir -p "$WS/.repo/manifests"

cat > "$WS/.repo/manifests/default.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <remote name="acme" fetch="ssh://git@git.acme.example/" review="git.acme.example"/>
  <default remote="acme" revision="main" sync-j="4"/>

  <project name="api-schema.git" path="services/api-schema"/>
  <project name="api-server.git" path="services/api-server"/>
  <project name="web-client.git" path="clients/web-client"/>

  <include name="tests.xml"/>
</manifest>
XML

# An include, because real manifests always have one.
cat > "$WS/.repo/manifests/tests.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <project name="e2e-suite.git" path="tests/e2e-suite" revision="stable"/>
</manifest>
XML

ln -s manifests/default.xml "$WS/.repo/manifest.xml"

for repo in services/api-schema services/api-server clients/web-client tests/e2e-suite; do
  mkdir -p "$WS/$repo"
  git -C "$WS/$repo" init -q
  echo "placeholder for $repo" > "$WS/$repo/README.md"
done

export DECK_ROOT="$WS"   # the pack comes later: the point here is generating the registry

cat <<BANNER

  An Acme workspace assembled by \`repo\` lives at
    $WS

  Four projects, declared across a manifest and one include.
  No descriptor yet.

BANNER

say "1. deck notices how the tree is assembled"
run init

export DECK_PACKS="$PACK"

say "2. What would the import add?"
run import repo

say "3. Fold it in"
run import repo --write

printf '\n\033[2m$ sed -n "/^repos:/,/^targets:/p" .deck/workspace.yaml\033[0m\n'
sed -n '/^repos:/,/^targets:/p' "$WS/.deck/workspace.yaml" | head -24

say "4. The half a manifest cannot answer"
run impact api-schema

cat <<'NOTE'

  Every repository is known, and the chain is empty. That is correct: the
  manifest declares a checkout, not a propagation. Nothing in it says that
  changing the schema forces the client to be regenerated.

  So we write the edges — once, by someone who knows the system.

NOTE

python3 - "$WS/.deck/workspace.yaml" <<'PY'
import re, sys, pathlib
path = pathlib.Path(sys.argv[1])
text = path.read_text()
edges = {
    "api-schema": ["api-server", "web-client", "e2e-suite"],
    "api-server": ["e2e-suite"],
    "web-client": ["e2e-suite"],
}
for name, targets in edges.items():
    text = re.sub(
        rf"(^  {re.escape(name)}:\n(?:    .*\n)*?    impacts:) \[\]$",
        lambda m, t=targets: m.group(1) + "\n" + "\n".join(f"    - {x}" for x in t),
        text,
        flags=re.M,
    )
text = re.sub(r"(^  e2e-suite:\n(?:    .*\n)*?    impacts: \[\]$)", r"\1\n    downstream: true", text, flags=re.M)
path.write_text(text)
print("  edges written into .deck/workspace.yaml")
PY

say "5. Now the same question has an answer"
run impact api-schema

say "6. And the pack still supplies the domain"
run toggle explain api_compat

if [ "$KEEP" = "--keep" ]; then
  printf '\n  Workspace kept at %s\n    export DECK_ROOT=%s && %s console\n\n' "$WS" "$WS" "$DECK"
else
  printf '\n  Workspace removed. Run with --keep to explore it yourself.\n'
fi
