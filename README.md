# deck-acme

An example extension pack for [deck](https://github.com/devfilipe/deck), plus a
demo that materialises a throwaway workspace and walks through it.

Acme is a small SaaS: an OpenAPI contract, a server, a web client generated from
the contract, and an end-to-end suite. Nothing here is real, and that is the
point — **deck has never heard of Acme.** Everything domain-specific below
arrives from `pack/config/*.yaml` as declarative data.

## Try it

```bash
git clone https://github.com/devfilipe/deck.git
git clone https://github.com/devfilipe/deck-acme.git
cd deck-acme && ./demo.sh
```

The demo builds a four-repository workspace in `mktemp -d`, points deck at this
pack, and shows six things. Add `--keep` to explore the workspace afterwards.

```
$ deck impact api-schema
a change in api-schema reaches 3 repositories

execution order:
  1. api-schema  build api-schema
  2. api-server  build api-server
  3. web-client  build web-client
  4. e2e-suite   (downstream — keep up, does not build)
```

## What the pack contributes

```
pack/
├── config/
│   ├── detect.yaml       markers that identify an Acme workspace, tools it needs
│   ├── toggles.yaml      three new decisions, three core ones relabelled
│   └── profiles.yaml     release, dark_launch
└── templates/workspace/
    └── workspace.yaml    a filled-in descriptor for this shape of workspace
```

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

## The point of this repository

It is the permanent agnosticism test. If a change to deck's engine cannot keep
Acme working without editing engine code, the change is in the wrong layer.

A second pack, for a Yocto embedded workspace, lives elsewhere with entirely
different rungs — schema compilation, bitbake targets, firmware bundles,
hardware benches. Same engine, no branches, no flags.

## Writing your own

Copy `pack/`, keep the structure, replace the content:

1. `detect.yaml` — one or two files only your workspace has, plus the tools
   `deck doctor` should check for.
2. `toggles.yaml` — the decisions your team keeps re-making. Give each one a
   question, options with descriptions, and the reason for the default.
3. `templates/workspace/workspace.yaml` — the repository registry with its
   `impacts` edges, and the target allowlist.

Point deck at it with `DECK_PACKS=/path/to/pack` or by listing it under `packs:`
in the descriptor.

## License

MIT © Filipe Denaur de Moraes
