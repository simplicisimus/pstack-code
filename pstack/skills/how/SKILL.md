---
name: how
description: "Use for \"how does X work\", code walkthroughs before changing something, and placement / ownership / layering questions (\"where should this live\", \"which package owns this\", \"is this the right layer\"). Explains subsystem architecture, runtime flow, onboarding mental models. Use why for motivation."
argument-hint: "[question]"
disable-model-invocation: true
---

# How

Explore the codebase to answer "how does X work?" questions. Produce architectural explanations at the level of a senior engineer onboarding onto a subsystem, enough to build a working mental model, not so much that it reads like annotated source code.

Every Claude spawn is an Agent subagent with `subagent_type: "pstack-code:reviewer"`, the read-only seat, or its `-<level>` copy when the effort rule needs one. Explorers use the `how explorer` line in `~/.claude/pstack-models.md` (written by `/setup-pstack`, default `sonnet`), and every explainer uses the `how explainer` line (default `opus`). Resolve each with `pstack-role --seat review --default <default> '<role line>'`. It applies the value grammar in the **setup-pstack** skill, falls back to the default when the file or the line is missing, and prints the `subagent_type` and `model` to use, or the brief of a bridge seat, which starts per the Bridge brief in the **setup-pstack** skill. If a spawn fails or a bridge replies `FAILED`, rerun it on the default and say so. Pick each subagent's effort for the job, per the Subagents section of the **poteto-mode** skill.

## 1. Assess complexity

If the scope is ambiguous, state your interpretation and explore. The user can redirect.

- **Simple** (a single module, a small utility, a narrow question such as "how does function X work"): no explorers. Spawn one explainer that explores and explains in one pass, built from `references/explainer-prompt.md` without the explorer-findings section. Go to step 4.
- **Complex** (a subsystem spanning multiple files or services, a cross-cutting feature, a full architectural overview): go to step 2.

When in doubt, take the simple path.

## 2. Explore (complex only)

Decompose the question into 2 to 4 angles, each a distinct slice of the subsystem. Spawn all explorers in a single message, each with `references/explorer-prompt.md` and its angle filled in.

## 3. Synthesize (complex only)

Once all explorers have returned, spawn one explainer with `references/explainer-prompt.md` and every explorer's findings filled in.

## 4. Present

Present the explainer's output. Light edits for clarity or context from the conversation are fine. Do not substantially rewrite it.

## Output format

The explanation uses the sections defined in `references/explainer-prompt.md`, dropping any that do not apply: Overview, Key Concepts, How It Works, Where Things Live, Gotchas.

## pstack on Claude Code

When you run this skill directly, `<pstack>` is `${CLAUDE_PLUGIN_ROOT}`, `<store>` is `${CLAUDE_PLUGIN_DATA}/store`, and this session's ID is `${CLAUDE_SESSION_ID}`. When poteto-mode, another pstack skill, or a brief sent you here, use the values it names. Other pstack skills named here (in bold, or as `principle-*`) live at `<pstack>/skills/<name>/SKILL.md`. They are user-invocable only, so Read them with the Read tool instead of the Skill tool. Per-role models come from `~/.claude/pstack-models.md` (see the **setup-pstack** skill). Cursor-specific terms, and a todolist in a session without a todo tool, map per `<pstack>/skills/poteto-mode/references/claude-code.md`.
