# Seam

A Claude Code plugin that enforces interface-first development. Code generation runs through a three-agent pipeline — **Architect**, **Critic**, **Developer** — so that contracts are designed and stress-tested for extensibility before any implementation is written.

## Why

Rapid AI-assisted code generation tends to produce tightly coupled, monolithic systems. LLMs optimize for immediate problem resolution and skip the architectural boundaries that make future change cheap. Seam inserts a structured multi-agent gate between the prompt and the implementation: the Architect designs only interfaces, the Critic stress-tests them against three plausible future features, and only on APPROVE does the Developer write concrete code against the finalized contracts.

There is no human approval step. The Critic is the sole architectural conscience — if it cannot articulate how three realistic future features could be added without modifying the interfaces, it rejects the draft and the Architect tries again. The loop is capped at three iterations; if the Critic still rejects on iteration three, the pipeline aborts and reports back instead of shipping rejected interfaces.

## Pipeline

```
User prompt
   │
   ▼
┌─────────────┐    REJECT (up to 3x)
│  Architect  │◀──────────────────┐
│  (opus)     │                   │
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

### Local testing

From the project root:

```bash
claude --plugin-dir /path/to/seam
```

### As a personal plugin

Copy or symlink the repo into your Claude Code plugins directory, then load it via `/plugin install` (see Claude Code docs for the current install command for your version).

## Usage

Inside a Claude Code session, run:

```
/seam-gen Create a document parsing service that supports XML and JSON sources
```

The orchestrator will:

1. Initialize `./.seam-work/`.
2. Loop Architect → Critic up to three times.
3. On APPROVE, invoke the Developer to write implementation files into `./src/`.
4. On three REJECTs, abort and surface the Critic's last report so you can refine the prompt.

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

The most important knob is the Critic's system prompt in `agents/critic.md`. The Critic must be willing to both REJECT (otherwise the workflow collapses into single-shot codegen) and APPROVE (otherwise every run aborts at iteration three). If your runs consistently end in three rejections, the Critic prompt is too strict for your domain — soften the calibration section. If runs always approve on iteration one with sloppy interfaces, the Critic is too lenient — strengthen the bias-toward-skepticism section.

## Plugin layout

```
seam/
├── .claude-plugin/
│   └── plugin.json
├── commands/
│   └── seam-gen.md         # /seam-gen orchestrator
└── agents/
    ├── architect.md        # interfaces only, model: opus
    ├── critic.md           # red-team review, model: sonnet
    └── developer.md        # concrete impl, model: sonnet
```
