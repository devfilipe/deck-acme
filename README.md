# deck-acme

[![ci](https://github.com/devfilipe/deck-acme/actions/workflows/ci.yml/badge.svg)](https://github.com/devfilipe/deck-acme/actions/workflows/ci.yml)

An example extension pack for [deck](https://github.com/devfilipe/deck), plus a
demo that materialises a throwaway workspace and walks through it.

Acme is a small SaaS: an OpenAPI contract, a server, a web client generated from
the contract, and an end-to-end suite. Nothing here is real, and that is the
point — **deck has never heard of Acme.** Everything domain-specific below
arrives from `packs/_workspace/config/*.yaml` as declarative data.

## Try it

```bash
git clone https://github.com/devfilipe/deck.git
git clone https://github.com/devfilipe/deck-acme.git
cd deck-acme && ./demo.sh
```

The demo builds a four-repository workspace in `mktemp -d`, points deck at this
pack, and walks one task from the board to the merge bundle: the impact graph,
the decisions and where each came from, the pack mounted into the repositories,
the ladder climbed, the number a rung kept across two runs, and the bundle a
reviewer reads instead of the diff. Add `--keep` to explore the workspace
afterwards.

There are two more demos. The first is one initiative inside the same
workspace:

```bash
./demo-scope.sh
```

`scopes:` names a subset of the registry — here `checkout`, which holds the
schema and the server and leaves the client out — and every command narrows to
it: its repositories, its board, its posture, and a pack bound to it that loads
under `deck --scope checkout` and nowhere else. It ends with a question the
catalog had no entry for being raised, answered by a person, and folded into
that pack as a catalog entry, so the next run reads a decision instead of
asking again.

The second is for the way large trees are usually assembled:

```bash
./demo-repo.sh
```

The same four projects, this time declared in a Google `repo` manifest with an
include. It shows `deck import repo` generating the registry, then the part an
importer cannot do — the `impacts` edges stay empty until someone who knows the
system writes them, and `deck impact` says so plainly until they do.

```
$ deck impact api-schema
a change in api-schema reaches 0 repositories

execution order:
  1. api-schema
```

The same is true of `targets:` and `scopes:`: a manifest declares a checkout, so
deck refuses to read a git remote as permission to reach a machine, and it will
not invent a carve-up nobody wrote down.

## What the pack contributes

```
packs/_workspace/          ← `_workspace` applies to every repository
├── config/
│   ├── detect.yaml       markers that identify an Acme workspace, tools it needs
│   ├── toggles.yaml      three new decisions, three core ones relabelled
│   ├── profiles.yaml     release, dark_launch
│   ├── gates.yaml        the verification ladder, with its own `contract` rung
│   └── mount.yaml        what deck places in a repository when this pack is used
├── rules/                `paths:`-scoped rules, placed on mount
└── templates/workspace/
    └── workspace.yaml    the registry, its `impacts` edges, the target
                          allowlist, the boards, and the `checkout` scope
```

### The ladder

```
ladder   static -> contract -> build -> deploy -> behavior
```

Acme inserts `contract` between lint and build, because an OpenAPI break is
worth catching before anything compiles. The engine never learns what that rung
means — it reads the rungs off the `gate_level` toggle, which this pack extends,
and runs the command each gate declares.

The deploy gate carries `when: {deploy_mode: [fast, packaged, full]}`, so while
that question is unanswered the gate reports *not applicable, deploy_mode is
`ask`* rather than quietly doing nothing.

The `contract` rung also keeps a number. `measures:` is a regex over output the
gate already produced, so nothing runs twice and no second command can disagree
with the first:

```yaml
measures:
  - id: published_paths
    pattern: '(\d+) paths published'
    unit: paths
```

No `better:`, deliberately — an API with more paths in it is neither better nor
worse, and `deck metrics show` says so: *2 -> 3 paths across 2 runs, +1 — no
`better:` is declared, so this is movement, not a verdict.* The engine keeps the
series without ever learning what an OpenAPI path is.

The command behind the rung is `sh ${path.contract_tools}/contract-diff.sh`. The
pack names the tool; `paths:` in the descriptor says where that checkout lives on
this machine, which is how the pack travels and the location stays yours.

### New decisions

| Toggle | Asks |
|---|---|
| `api_compat` | May this change alter the published API contract? |
| `migration_plan` | Does the schema change ship reversibly, in phases? |
| `feature_flag` | Should the new behaviour ship dark? |

Each carries its own question, the options a human sees, the impact of every
value, and the reasoning behind the default. The agent reads them; it does not
improvise them.

### Core decisions, relabelled

`deploy_mode` is a core concept — how far the artifact travels — and the pack
names the actual rungs, so the question a person answers reads in their own
vocabulary:

```yaml
- id: deploy_mode
  overrides: true          # without this flag the merge is refused
  question:
    options:
      - { value: fast,     label: Sync into the pod,    description: "Seconds, and diverges from the image the registry holds." }
      - { value: packaged, label: helm upgrade,         description: "Real chart, real image. The everyday path." }
      - { value: full,     label: Rebuild and roll out, description: "Faithful end to end, and the slowest." }
```

`gate_level` gains a rung: Acme inserts `contract` between lint and build,
because an OpenAPI break is worth catching before anything compiles.

The gate commands in `packs/_workspace/config/gates.yaml` echo, or call a
stand-in script, rather than build, so the demos run anywhere in a second with no
toolchain installed. Everything around them is real: the rungs, the `when`
conditions, the per-repository scoping, the number the contract rung keeps, and
the evidence the engine records.

### One initiative

```yaml
scopes:
  checkout:
    title: Checkout hardening
    repos: [api-schema, api-server]
```

Four lines in the pack's template, and every command has a narrowed form. The
one that earns its place is `deck scope checkout`, which reports what the
boundary *leaks* — `reaches web-client, e2e-suite (outside the scope, still has
to keep up)` — because an initiative drawn around two of four repositories is a
claim about attention, not about the graph, and the graph is unchanged.

## What the demos exercise

Between them the three scripts drive most of deck's surface against a domain it
has never heard of.

| | Commands |
|---|---|
| `demo.sh` | `doctor` · `impact` · `order` · `paths` · `toggle` (list, explain, get, set, profile, ask-plan) · `board` (show, why, claim, done) · `mount` · `mounts` · `unmount` · `gate` (list, run) · `metrics show` · `bundle` |
| `demo-scope.sh` | `scopes` · `scope` · `--scope` · `repos` · `packs` · `pack` (new, validate) · `ask` (new, list, resolve, fold) · `toggle` (set at a scope, explain) · `board list` · `impact` |
| `demo-repo.sh` | `init` · `import repo` · `impact` · `targets` · `scopes` · `toggle explain` |

Still untouched: `root`, `info`, `path`, `get`, `setup`, `hold`,
`propose`, `cost`, `gate report`, `board` (plan, new, template, ask-plan,
whoami), `pack` (list, review, sources, add, update), `console`, `ui`,
`statusline`.

## The point of this repository

It is the permanent agnosticism test. If a change to deck's engine cannot keep
Acme working without editing engine code, the change is in the wrong layer.

A second pack, for a Yocto embedded workspace, lives elsewhere with entirely
different rungs — schema compilation, bitbake targets, firmware bundles,
hardware benches. Same engine, no branches, no flags.

## Writing your own

Copy `packs/_workspace/`, keep the structure, replace the content:

1. `detect.yaml` — one or two files only your workspace has, plus the tools
   `deck doctor` should check for.
2. `toggles.yaml` — the decisions your team keeps re-making. Give each one a
   question, options with descriptions, and the reason for the default.
3. `templates/workspace/workspace.yaml` — the repository registry with its
   `impacts` edges, the target allowlist, and — if the work is carved into
   initiatives — `scopes:`, which belongs here rather than in one person's
   `.deck/` because a scope only your machine declares is a scope only you have.

Point deck at it with `DECK_PACKS=/path/to/pack` or by listing it under `packs:`
in the descriptor.

## License

MIT © Filipe Denaur de Moraes
