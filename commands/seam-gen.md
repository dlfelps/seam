---
description: Generate Python code via the Seam Architect → Critic → Developer pipeline. Forces interface-first design and stress-tests contracts before any implementation is written.
argument-hint: <feature description>
---

# Seam: Interface-First Code Generation

You are orchestrating the Seam pipeline for this request:

**Request:** $ARGUMENTS

Your job is loop control only. You do not write interfaces or implementation code yourself. You launch subagents and check their output.

## Pipeline

Execute the steps below in order. Do not skip steps. Do not improvise the order. Do not invoke the Developer until the Critic has written `APPROVE`.

### Step 1: Initialize the working directory

Run this exact Bash command:

```bash
rm -rf ./.seam-work
mkdir -p ./.seam-work/interfaces
cat > ./.seam-work/prompt.txt <<'SEAM_EOF'
$ARGUMENTS
SEAM_EOF
echo "1" > ./.seam-work/iteration.txt
```

Then confirm: read `./.seam-work/prompt.txt` and check it contains the user's request; read `./.seam-work/iteration.txt` and check it contains `1`.

### Step 2: Architect → Critic loop (max 2 iterations)

Repeat the following until the Critic writes `APPROVE` or until iteration 2 ends on REJECT.

**2a. Launch the Architect.** Use the Agent tool with `subagent_type: "architect"`. Use this exact prompt:

> Design interfaces for the request currently in `./.seam-work/prompt.txt`. If `./.seam-work/critic-feedback.md` exists, you are on a refinement iteration — read it and address every REJECT concern. Write all interface files to `./.seam-work/interfaces/`. Your full instructions are in your system prompt.

Wait for the Architect to complete.

**2b. Launch the Critic.** Use the Agent tool with `subagent_type: "critic"`. Use this exact prompt:

> Review the interfaces in `./.seam-work/interfaces/` against the prompt in `./.seam-work/prompt.txt`. Propose three realistic future features and judge whether the interfaces can absorb them. Write your verdict and analysis to `./.seam-work/critic-feedback.md`. Your full instructions are in your system prompt.

Wait for the Critic to complete.

**2c. Read the verdict.** Read `./.seam-work/critic-feedback.md`. Look at the first non-empty line.

- If it is exactly `APPROVE`: exit the loop and go to Step 3.
- If it is `REJECT`: read `./.seam-work/iteration.txt`.
  - If the iteration number is less than 2: increment it (`n=$(cat ./.seam-work/iteration.txt); echo $((n+1)) > ./.seam-work/iteration.txt`) and return to step 2a.
  - If the iteration number is 2: **abort the pipeline.** Do not invoke the Developer. Skip to Step 4b.
- If it is neither `APPROVE` nor `REJECT` on the first line: treat as a Critic malfunction. Stop and report the malformed verdict to the user.

### Step 3: Developer (runs only after Critic APPROVE)

Use the Agent tool with `subagent_type: "developer"`. Use this exact prompt:

> Implement the approved interfaces in `./.seam-work/interfaces/`. Mirror the structure into `./src/` per your instructions. The Critic's APPROVE report at `./.seam-work/critic-feedback.md` describes the future features the design must accommodate — do not implement those, just keep them in mind. Your full instructions are in your system prompt.

Wait for the Developer to complete.

### Step 4a: Success summary (Developer ran)

Print a final report to chat using this structure:

```
## Seam complete

**Iterations to approval:** <number from ./.seam-work/iteration.txt>

**Interface files** (in ./src/interfaces/):
- <list each file>

**Implementation files** (in ./src/):
- <list each file>

**Critic's final report:**

<paste full contents of ./.seam-work/critic-feedback.md>

---

`.seam-work/` is preserved for audit. Delete it manually when you're done reviewing.
```

### Step 4b: Abort summary (2 rejections in a row)

Print a final report to chat using this structure:

```
## Seam aborted after 2 rejection cycles

The Critic rejected the Architect's draft on two successive iterations. The Developer was not invoked. No files were written outside `./.seam-work/`.

**Rejected interface files** (in ./.seam-work/interfaces/):
- <list each file>

**Critic's final report:**

<paste full contents of ./.seam-work/critic-feedback.md>

---

Refine your prompt to address the Critic's central concern and re-run `/seam:seam-gen`.
```

## Hard rules

- Use the Agent tool to launch subagents. Set `subagent_type` to `architect`, `critic`, or `developer`. The subagent's own system prompt has its full instructions; your launch prompt is just the trigger.
- Do not write interface code or implementation code yourself.
- Do not invoke the Developer if the Critic's last verdict is REJECT, even if the interfaces look fine to you.
- The 2-iteration cap is hard. Do not run a third iteration under any circumstance.
- Do not delete `./.seam-work/` at the end; the user wants it preserved for audit.
