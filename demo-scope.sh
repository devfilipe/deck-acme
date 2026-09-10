#!/usr/bin/env bash
# One initiative inside the Acme workspace, and the question it raised.
#
# A workspace of four repositories is rarely one piece of work. `scopes:` names
# a subset of the registry and gives it a board, a posture and a pack of its
# own — and this tour ends with a question the catalog had no entry for being
# written into that pack, so nobody has to ask it twice.
#
#   ./demo-scope.sh            run the tour
#   ./demo-scope.sh --keep     leave the workspace on disk
set -euo pipefail

PACKS="$(cd "$(dirname "${BASH_SOURCE[0]}")/packs" && pwd)"
PACK="$PACKS/_workspaces/all/default"
KEEP="${1:-}"

if [ -n "${DECK_BIN:-}" ]; then
  DECK="$DECK_BIN"
elif command -v deck >/dev/null; then
  DECK="$(command -v deck)"
elif [ -x "$(dirname "$PACKS")/../deck/plugins/deck/bin/deck" ]; then
  DECK="$(cd "$(dirname "$PACKS")/../deck" && pwd)/plugins/deck/bin/deck"
else
  echo "deck not found. Set DECK_BIN, or clone github.com/devfilipe/deck next to this one." >&2
  exit 1
fi

WS="$(mktemp -d)"
[ "$KEEP" = "--keep" ] || trap 'rm -rf "$WS"' EXIT

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
note() { printf '\n%s\n' "$1"; }
run() {
  local shown=() a
  for a in "$@"; do
    case "$a" in *[[:space:]]*) shown+=("\"$a\"") ;; *) shown+=("$a") ;; esac
  done
  printf '\n\033[2m$ deck %s\033[0m\n' "${shown[*]}"
  "$DECK" "$@"
}

# --------------------------------------------------------- build the workspace
: > "$WS/.acme-root"
echo '{ "name": "acme" }' > "$WS/package.json"
mkdir -p "$WS/docs" "$WS/tools/openapi" "$WS/.deck" "$WS/packs"
printf '# Roadmap\n\n- [ ] rate limiting\n- [ ] audit log\n' > "$WS/docs/roadmap.md"

cat > "$WS/docs/board.yaml" <<'BOARD'
version: 1
tasks:
  - id: ACME-11
    title: Idempotency key on the checkout endpoint
    repos: [api-schema, api-server]
    status: open
  - id: ACME-14
    title: Retire the legacy order list widget
    repos: [web-client]
    status: open
BOARD

for repo in services/api-schema services/api-server clients/web-client tests/e2e-suite; do
  mkdir -p "$WS/$repo"
  git -C "$WS/$repo" init -q
  printf '{ "name": "%s", "scripts": { "lint": "echo lint ok" } }\n' "$(basename "$repo")" > "$WS/$repo/package.json"
done
printf 'openapi: 3.1.0\ninfo: { title: Acme API, version: 1.0.0 }\npaths:\n  /orders:\n' \
  > "$WS/services/api-schema/openapi.yaml"

# Two pack roots: this repository's, which is versioned and read-only here, and
# an empty one in the workspace where the initiative's own pack will be written.
sed -e "s|^packs_root: \[\]|packs_root: [$PACKS, $WS/packs]|" \
    -e "s|^paths: {}|paths: { contract_tools: $WS/tools/openapi }|" \
    "$PACK/templates/workspace/workspace.yaml" > "$WS/.deck/workspace.yaml"

export DECK_ROOT="$WS"
export DECK_USER="someone@example.com"

cat <<BANNER

  The same four-repository Acme workspace, at
    $WS

  The carve-up below is not this machine's opinion: it arrives in
    packs/_workspaces/all/default/templates/workspace/workspace.yaml

BANNER

say "1. How is this registry carved up?"
run scopes

say "2. One initiative, in full"
run scope checkout
note "  Two lines are worth reading twice. \`reaches\` is what the boundary leaks —
  a change inside the scope still forces work outside it, and deck says so
  before the work starts rather than at the merge. \`posture\` is empty because
  nobody has recorded one yet."

say "3. Every command narrows to it"
run --scope checkout repos
run --scope checkout board list
note "  There is no separate file: the scope reads the workspace board and keeps the
  tasks its repositories cover. The roadmap entries name no repository, so no
  scope can claim them, and deck reports that instead of guessing."
run --scope checkout impact api-schema
note "  Narrowing never changes what the graph knows. web-client is still reached,
  and marked \`[outside scope]\` so nobody mistakes a boundary for an absence."

say "4. A posture of its own"
run --scope checkout toggle set api_compat strict --at checkout \
  --why "every checkout client in the field reads this contract"
run scope checkout

say "5. A pack that belongs to the initiative and nothing else"
run pack new all/checkout --from-workspace \
  --dir "$WS/packs/_workspaces/all/checkout" \
  --description "What the checkout initiative knows, and nobody else needs"
run packs
note "  Written but not loaded. The knowledge stays findable — \`deck packs\` lists it
  either way — and reaches an agent only while the initiative is the one being
  worked on:"
run --scope checkout packs

say "6. A question the catalog has no entry for"
run ask new "May a checkout retry arrive without an idempotency key?" \
  --task ACME-11 \
  --context "The contract does not say, and the two answers differ by a duplicate charge." \
  --options "reject,accept-and-log"
ASK="$("$DECK" ask list --json | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["id"])')"
run ask list

say "7. Someone answers it"
run ask resolve "$ASK" \
  "It must reject the request. A checkout retry with no idempotency key is a new charge, so the endpoint answers 400 and the code idempotency_key_required." \
  --who "someone@example.com"

say "8. deck will not invent the half the answer does not contain"
run ask fold "$ASK" --as toggle --into "$WS/packs/_workspaces/all/checkout" || true
note "  The answer defended one value; a catalog entry has to say what the others
  are for. The other two shapes refuse on the same principle: a rule with no
  \`--paths\` loads on every turn whether or not it is relevant, and a gate with
  no \`--command\` is a check nobody can run."

say "9. Fold it, with the missing half supplied"
run ask fold "$ASK" --as toggle --into "$WS/packs/_workspaces/all/checkout" \
  --gate-id retry_without_key --group quality --header "Retry key" \
  --title "Retry without an idempotency key" \
  --impact "reject=400 idempotency_key_required. A duplicate charge cannot be created by a retry." \
  --impact "accept-and-log=The retry is served and recorded. Only sound where the operation cannot charge twice."

printf '\n\033[2m$ sed -n "/^# Folded from/,\$p" packs/_workspaces/all/checkout/config/toggles.yaml\033[0m\n'
sed -n '/^# Folded from/,$p' "$WS/packs/_workspaces/all/checkout/config/toggles.yaml"

say "10. It is a decision now, not a transcript"
run --scope checkout toggle explain retry_without_key
run pack validate "$WS/packs/_workspaces/all/checkout"
note "  And outside the initiative it does not exist, because the pack that holds it
  is bound to one:"
run toggle explain retry_without_key || true

if [ "$KEEP" = "--keep" ]; then
  printf '\n  Workspace kept at %s\n    export DECK_ROOT=%s && %s --scope checkout console\n\n' "$WS" "$WS" "$DECK"
else
  printf '\n  Workspace removed. Run with --keep to explore it yourself.\n'
fi
