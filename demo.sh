#!/usr/bin/env bash
# Materialise a throwaway Acme workspace and take deck for a walk through it.
#
#   ./demo.sh            run the tour
#   ./demo.sh --keep     leave the workspace on disk and print its path
#
# Nothing is created outside a temporary directory, so this is safe to run
# anywhere, as many times as you like.
set -euo pipefail

PACKS="$(cd "$(dirname "${BASH_SOURCE[0]}")/packs" && pwd)"
PACK="$PACKS/_workspace"
KEEP="${1:-}"

# Find deck: an explicit path, then $PATH, then a sibling clone.
if [ -n "${DECK_BIN:-}" ]; then
  DECK="$DECK_BIN"
elif command -v deck >/dev/null; then
  DECK="$(command -v deck)"
elif [ -x "$(dirname "$PACKS")/../deck/plugins/deck/bin/deck" ]; then
  DECK="$(cd "$(dirname "$PACKS")/../deck" && pwd)/plugins/deck/bin/deck"
else
  echo "deck not found. Set DECK_BIN=/path/to/deck, or clone" >&2
  echo "https://github.com/devfilipe/deck next to this repository." >&2
  exit 1
fi

WS="$(mktemp -d)"
[ "$KEEP" = "--keep" ] || trap 'rm -rf "$WS"' EXIT

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
run() { printf '\n\033[2m$ deck %s\033[0m\n' "$*"; "$DECK" "$@"; }

# ---------------------------------------------------------- build the workspace
: > "$WS/.acme-root"                    # the marker the pack declares
echo '{ "name": "acme" }' > "$WS/package.json"
mkdir -p "$WS/docs"
printf '# Roadmap\n\n- [ ] rate limiting\n- [ ] audit log\n' > "$WS/docs/roadmap.md"

for repo in services/api-schema services/api-server clients/web-client tests/e2e-suite; do
  mkdir -p "$WS/$repo"
  git -C "$WS/$repo" init -q
  echo "placeholder for $repo" > "$WS/$repo/README.md"
  printf '{ "name": "%s", "scripts": { "lint": "echo lint ok" } }\n' "$(basename "$repo")" > "$WS/$repo/package.json"
done
printf 'openapi: 3.1.0\ninfo: { title: Acme API, version: 1.0.0 }\n' \
  > "$WS/services/api-schema/openapi.yaml"

mkdir -p "$WS/.deck"
sed "s|^packs_root: \[\]|packs_root: [$PACKS]|" packs/_workspace/templates/workspace/workspace.yaml > "$WS/.deck/workspace.yaml"

export DECK_ROOT="$WS"

cat <<BANNER

  A four-repository Acme workspace has been created at
    $WS

  deck has never heard of Acme. Everything below comes from
    pack/config/*.yaml

BANNER

say "1. Is this workspace usable?"
run doctor || true

say "2. What does a schema change reach, and in what order?"
run impact api-schema

say "3. What is decided, and where did each value come from?"
run toggle list --stage verify

say "4. A domain decision the core knows nothing about"
run toggle explain api_compat

say "5. What would the agent ask before deploying?"
printf '\n\033[2m$ deck toggle ask-plan --stage verify --files services/api-schema/openapi.yaml\033[0m\n'
"$DECK" toggle ask-plan --stage verify --files services/api-schema/openapi.yaml |
  python3 -c '
import json, sys
plan = json.load(sys.stdin)
for q in plan["questions"]:
    print()
    print("  " + q["question"] + "   [" + q["risk"] + " risk]")
    for o in q["options"]:
        print("    {:<24} {}".format(o["label"], o["description"]))
for a in plan["assumed"]:
    print()
    print("  assumed {}={} ({})".format(a["id"], a["value"], a["reason"]))
'

say "6. Switch posture in one phrase"
run toggle profile release --at task
run toggle get test_depth
run toggle get api_compat

say "7. The verification ladder, declared by this pack"
run gate list --repos api-schema

say "8. Climb it"
run toggle set deploy_mode packaged --at task
run gate run --task DEMO --repos api-schema

if [ "$KEEP" = "--keep" ]; then
  cat <<KEPT

  Workspace kept at $WS
  Explore it with:
    export DECK_ROOT=$WS
    $DECK console

KEPT
else
  echo
  echo "  Workspace removed. Run with --keep to explore it yourself."
fi
