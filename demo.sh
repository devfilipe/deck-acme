#!/usr/bin/env bash
# Materialise a throwaway Acme workspace and take deck for a walk through it,
# from an open task to the bundle a reviewer reads at the end.
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
note() { printf '\n%s\n' "$1"; }
run() {                                 # echo the command, then run it
  local shown=() a
  for a in "$@"; do
    case "$a" in *[[:space:]]*) shown+=("\"$a\"") ;; *) shown+=("$a") ;; esac
  done
  printf '\n\033[2m$ deck %s\033[0m\n' "${shown[*]}"
  "$DECK" "$@"
}

# The name a claim and a commit are published under. A fictional address, since
# this workspace is fictional; yours comes from $DECK_USER or git's user.name.
export DECK_USER="someone@example.com"
GIT_AS=(-c user.name="Acme Developer" -c user.email="someone@example.com")

# ---------------------------------------------------------- build the workspace
: > "$WS/.acme-root"                    # the marker the pack declares
echo '{ "name": "acme" }' > "$WS/package.json"
mkdir -p "$WS/docs" "$WS/tools/openapi"
printf '# Roadmap\n\n- [ ] rate limiting\n- [ ] audit log\n' > "$WS/docs/roadmap.md"

# The board the team writes tasks on. deck reads this shape and writes it back.
cat > "$WS/docs/board.yaml" <<'BOARD'
version: 1
tasks:
  - id: ACME-11
    title: Idempotency key on the checkout endpoint
    repos: [api-schema, api-server]
    status: open
    acceptance:
      - A repeated request carrying the same key returns the first result
      - The key is published in the contract, not inferred by the client
  - id: ACME-14
    title: Retire the legacy order list widget
    repos: [web-client]
    status: open
BOARD

# The contract differ the `contract` gate calls. It is a stand-in — a real one
# diffs against the published schema — but it is a real external tool as far as
# the pack is concerned, which is the point of `paths:` below.
cat > "$WS/tools/openapi/contract-diff.sh" <<'TOOL'
#!/bin/sh
# usage: contract-diff.sh <openapi file>
echo "$(grep -c '^  /' "$1") paths published"
echo "contract diff clean (stub)"
TOOL

for repo in services/api-schema services/api-server clients/web-client tests/e2e-suite; do
  mkdir -p "$WS/$repo"
  git -C "$WS/$repo" init -q
  echo "placeholder for $repo" > "$WS/$repo/README.md"
  printf '{ "name": "%s", "scripts": { "lint": "echo lint ok" } }\n' "$(basename "$repo")" > "$WS/$repo/package.json"
done
printf 'openapi: 3.1.0\ninfo: { title: Acme API, version: 1.0.0 }\npaths:\n  /orders:\n  /orders/{id}:\n' \
  > "$WS/services/api-schema/openapi.yaml"
for repo in services/api-schema services/api-server clients/web-client tests/e2e-suite; do
  git -C "$WS/$repo" add -A
  git -C "$WS/$repo" "${GIT_AS[@]}" commit -qm "initial import"
done

mkdir -p "$WS/.deck"
sed -e "s|^packs_root: \[\]|packs_root: [$PACKS]|" \
    -e "s|^paths: {}|paths: { contract_tools: $WS/tools/openapi }|" \
    "$PACK/templates/workspace/workspace.yaml" > "$WS/.deck/workspace.yaml"

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
note "  The same graph answers a second question — hand it an unordered set and it
  sorts it, dropping what produces nothing:"
run order e2e-suite web-client api-schema

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

say "7. Take a task, and be told what would make it right"
run board show ACME-11
note "  A title says what to touch. The acceptance criteria say what would make it
  right, and deck refuses to close the task without them later.

  It also knows which tasks may not run beside each other, because it knows what
  each one reaches:"
run board why ACME-11 ACME-14
run board claim ACME-11 --yes

say "8. Put the pack where the agent will read it"
run mount --task ACME-11 --repos api-schema --dry-run
note "  One repository was named and four are listed: mount follows the same impact
  graph as step 2. Now for real, with a sentence saying what the task is for:"
printf '\n\033[2m$ deck mount --task ACME-11 --repos api-schema --brief -\033[0m\n'
printf 'ACME-11 — a repeated checkout request carrying the same idempotency key must
return the first result rather than charging again.\n' |
  "$DECK" mount --task ACME-11 --repos api-schema --brief -
run mounts

say "9. The verification ladder, declared by this pack"
run gate list --repos api-schema
note "  The \`contract\` rung runs \`sh \${path.contract_tools}/contract-diff.sh\`. The
  pack names the tool; the workspace says where that checkout is, so the pack
  travels and the location stays local:"
run paths

say "10. Take the number before touching anything"
run gate run --task ACME-11 --level contract
note "  \`published_paths\` is not a rung and cannot fail anything. The pack declared
  a regex over output the gate already produced, so the engine keeps a series
  without learning what an OpenAPI path is."

say "11. The change itself"
printf 'openapi: 3.1.0\ninfo: { title: Acme API, version: 1.1.0 }\npaths:\n  /orders:\n  /orders/{id}:\n  /orders/{id}/refund:\n' \
  > "$WS/services/api-schema/openapi.yaml"
git -C "$WS/services/api-schema" add -A
git -C "$WS/services/api-schema" "${GIT_AS[@]}" \
  commit -qm "ACME-11: publish the refund path, keyed by the idempotency key"
printf '\n  services/api-schema/openapi.yaml gains one path, committed with the task id\n  in the message. That is the whole basis on which the bundle attributes it.\n'

say "12. Climb the ladder"
run toggle set deploy_mode packaged --at task --why "the everyday path for a checkout change"
run gate run --task ACME-11

say "13. The number the rung kept"
run metrics show contract.published_paths

say "14. Close it, take the context back, hand over the bundle"
run board done ACME-11 --yes \
  --accept "A repeated request carrying the same key returns the first result" \
  --accept "The key is published in the contract, not inferred by the client"
run unmount --task ACME-11

note "  That is deck's report of what it took back. This repository exists to check
  claims rather than repeat them, so the demo asks git the same question —
  with the reader's personal ignore rules switched off, because a promise that
  only holds on machines carrying the right ~/.config/git/ignore is not one:"

printf '\n\033[2m$ git -C <each repository> -c core.excludesFile=/dev/null status --porcelain\033[0m\n'
LEFTOVERS=""
for repo in services/api-schema services/api-server clients/web-client tests/e2e-suite; do
  dirty="$(git -C "$WS/$repo" -c core.excludesFile=/dev/null status --porcelain)"
  if [ -n "$dirty" ]; then
    LEFTOVERS="$LEFTOVERS $repo"
    printf '  %-14s %s\n' "$(basename "$repo")" "$(echo "$dirty" | tr '\n' ' ')"
  else
    printf '  %-14s clean\n' "$(basename "$repo")"
  fi
done

if [ -n "$LEFTOVERS" ]; then
  cat <<'LEFT'

  The unmount above said `0 left alone` and exited 0, and something is still
  there. What survives is `.claude/settings.local.json`, holding the
  `extraKnownMarketplaces` entry deck wrote on mount: the manifest records the
  plugins it added and not the marketplace, so unmount takes back one of the two
  things mount wrote and keeps the file alive for the other. The same unmount
  drops deck's `.git/info/exclude` block, so the leftover becomes visible to
  `git status` at the exact moment deck stops hiding it.

  Nothing here is Acme's to fix. `deck bundle` would refuse the merge over the
  dirty tree next, and it would be right to; the demo stops here instead, so
  the reason is the leftover rather than the verdict about it.

LEFT
  exit 1
fi

note "  Now the page a reviewer reads instead of the diff:"
run bundle --task ACME-11
note "  READY is a claim with a file behind every line of it, and the note left open
  is honest rather than tidy: three repositories this change reaches carry no
  commit under the task. That is either deliberate or a chain that stopped
  early, and deck declines to decide which."

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
