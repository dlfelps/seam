# Seam

A Claude Code plugin that enforces interface-first development. Code generation runs through a three-agent pipeline — **Architect**, **Critic**, **Developer** — so that contracts are designed and stress-tested for extensibility before any implementation is written.

## Why

Rapid AI-assisted code generation tends to produce tightly coupled, monolithic systems. LLMs optimize for immediate problem resolution and skip the architectural boundaries that make future change cheap. Seam inserts a structured multi-agent gate between the prompt and the implementation: the Architect designs only interfaces, the Critic stress-tests them against three plausible future features, and only on APPROVE does the Developer write concrete code against the finalized contracts.

There is no human approval step. The Critic is the sole architectural conscience — if it cannot articulate how three realistic future features could be added without modifying the interfaces, it rejects the draft and the Architect tries again. The loop is capped at two iterations; if the Critic still rejects on iteration two, the pipeline aborts and reports back instead of shipping rejected interfaces.

## Pipeline

```
User prompt
   │
   ▼
┌─────────────┐    REJECT (up to 2x)
│  Architect  │◀──────────────────┐
│  (sonnet)   │                   │
└─────────────┘                   │
   │ writes interfaces            │
   ▼                              │
┌─────────────┐                   │
│   Critic    │───────────────────┘
│  (sonnet)   │
└─────────────┘
   │ APPROVE
   ▼
┌─────────────┐
│  Developer  │
│  (sonnet)   │── writes ./src/
└─────────────┘
```

State is passed via files in `./.seam-work/`:

- `prompt.txt` — original request
- `interfaces/` — current Architect draft
- `critic-feedback.md` — latest verdict (first line `APPROVE` or `REJECT`)
- `iteration.txt` — refinement loop counter

## Installation

Seam is distributed as a single-plugin marketplace hosted from this repository. Inside a Claude Code session, add the marketplace and then install the plugin:

```
/plugin marketplace add dlfelps/seam
/plugin install seam@seam
```

Verify the install:

```
/plugin list
```

You should see `seam` in the enabled plugins list. Plugin slash commands are namespaced by plugin name, so the orchestrator is invoked as `/seam:seam-gen`.

### Updating

When a new version is published, pull the latest marketplace catalog and reinstall:

```
/plugin marketplace update seam
/plugin install seam@seam
```

### Local development

To iterate on the plugin from a working copy, add the local directory as a marketplace instead of the GitHub repo:

```
/plugin marketplace add /path/to/seam
/plugin install seam@seam
```

### Uninstalling

```
/plugin uninstall seam@seam
/plugin marketplace remove seam
```

## Usage

Inside a Claude Code session, run:

```
/seam:seam-gen Create a document parsing service that supports XML and JSON sources
```

The orchestrator will:

1. Initialize `./.seam-work/`.
2. Loop Architect → Critic up to two times.
3. On APPROVE, invoke the Developer to write implementation files into `./src/`.
4. On two REJECTs, abort and surface the Critic's last report so you can refine the prompt.

After a successful run you'll have:

```
./src/
├── __init__.py
├── interfaces/
│   ├── __init__.py
│   └── *_interface.py
└── *.py                  # concrete implementations
```

`./.seam-work/` is preserved for audit. Delete it manually when done.

## Output language

The MVP targets Python 3.10+. Interfaces are written using `abc.ABC` + `@abstractmethod` or `typing.Protocol`; data shapes use `dataclasses` or `TypedDict`.

## Tuning

The most important knob is the Critic's system prompt in `agents/critic.md`. The Critic must be willing to both REJECT (otherwise the workflow collapses into single-shot codegen) and APPROVE (otherwise every run aborts at iteration two). If your runs consistently end in two rejections, the Critic prompt is too strict for your domain — soften the calibration section. If runs always approve on iteration one with sloppy interfaces, the Critic is too lenient — strengthen the bias-toward-skepticism section.

## Plugin layout

```
seam/
├── .claude-plugin/
│   ├── plugin.json         # plugin manifest
│   └── marketplace.json    # marketplace catalog (this repo is a one-plugin marketplace)
├── commands/
│   └── seam-gen.md         # /seam:seam-gen orchestrator
├── agents/
│   ├── architect.md        # interfaces only, model: sonnet
│   ├── critic.md           # red-team review, model: sonnet
│   └── developer.md        # concrete impl, model: sonnet
└── LICENSE
```

## Publishing

### Validate the manifests

Before tagging a release or submitting upstream, run the bundled validator. It checks `.claude-plugin/marketplace.json` and `.claude-plugin/plugin.json` against the same schema the community-marketplace review pipeline uses:

```bash
claude plugin validate .            # warns on issues but allows minor ones
claude plugin validate --strict .   # fails on warnings — use this in CI
```

A clean run prints `√ Validation passed`.

### Submit to the Anthropic community marketplace

Anthropic operates a public, third-party-friendly catalog at [`anthropics/claude-plugins-community`](https://github.com/anthropics/claude-plugins-community) (installable as `@claude-community`). Submission is done through an in-app form:

- https://claude.ai/settings/plugins/submit
- https://platform.claude.com/plugins/submit

Workflow:

1. Run `claude plugin validate --strict .` and fix anything it reports.
2. Tag a release (for example `v0.1.0`) so the catalog can pin to a meaningful ref.
3. Submit the GitHub URL (`https://github.com/dlfelps/seam`) via either form above.
4. The review pipeline runs the same validator plus automated safety screening.
5. On approval, the plugin is pinned to a specific commit SHA in the catalog. CI bumps the pin as new commits land on the default branch.
6. The public catalog syncs nightly, so there is a delay between approval and the listing appearing. To check status, search for `seam` in [the live `marketplace.json`](https://github.com/anthropics/claude-plugins-community/blob/main/.claude-plugin/marketplace.json).

Once listed, users install with:

```
/plugin marketplace add anthropics/claude-plugins-community
/plugin install seam@claude-community
```

> Note: the separate, curated `claude-plugins-official` marketplace has no application process. Anthropic decides what to include there at its discretion; the submission forms above only feed `claude-community`.

## License

[MIT](./LICENSE)
