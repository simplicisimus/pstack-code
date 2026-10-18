---
name: interrogate
description: "Use for \"interrogate\", \"adversarial review\", \"multi-model review\", \"challenge this\", \"stress test this code\", \"find blind spots\", or \"tear this apart\". Multiple LLM reviewers challenge changes from independent angles."
argument-hint: "[PR, diff, or files]"
disable-model-invocation: true
---

# Interrogate

Spawn one reviewer per configured model to adversarially review code changes. The adversarial signal comes from model diversity, not assigned personas. The deliverable is a synthesized verdict. Do NOT auto-apply changes.

## Step 1, Scope

Identify what to review from context:

- If the user points at specific files or a diff, use that.
- If on a feature branch, run `git diff main...HEAD` (or the appropriate base branch) for the full changeset.
- If the user's message references recent work, gather the relevant files.

Package the diff or file contents with any surrounding context files the reviewers need to understand the code.

## Step 2, Intent

Before spawning reviewers, state the intent in one clear paragraph from the user's message, commit messages, the PR description if one exists, and the code. If you're unsure about the intent, ask the user before proceeding.

## Step 3, Spawn Reviewers

Launch all reviewers in a single message, one per entry on the `interrogate reviewers` line in `~/.claude/pstack-models.md`, labeled Reviewer A, B, and so on to match the entry count. If the rule or that line is missing, use the table defaults.

| Subagent | Default model |
|----------|---------------|
| Reviewer A | `opus` |
| Reviewer B | `sonnet` |

Each reviewer gets `subagent_type: "pstack-code:reviewer"`, the read-only seat, and `model` set to its configured entry, or its table default when there is no configured line.

Resolve the line with `pstack-role --seat review --panel --default 'opus, sonnet' 'interrogate reviewers'`. It applies the value grammar in the **setup-pstack** skill and prints one line per reviewer with its `subagent_type`, its `model` when one applies, and the brief of a bridge seat. External reviewers get `Mode: review`, and the filled template below is their prompt file. Claude reviewers and bridge agents are Agent calls. A `codex:` or `grok:` reviewer that you start from the main conversation is a background `pstack-seat` call, per the Bridge brief in the **setup-pstack** skill. If a configured entry fails to spawn or a bridge replies `FAILED`, run that reviewer on its table default and say so. A disabled alias drops its reviewer instead.

Read `references/reviewer-prompt.md` and fill in the same template for every reviewer with the stated intent, the diff or file contents, the rubric from `references/rubric.md`, and the code-quality lens from `references/code-quality-review.md`. Pick each subagent's effort for the job, per the Subagents section of the **poteto-mode** skill.

## Step 4, Synthesize

As results come back, build a unified picture. Parse every reviewer's findings. Merge findings that describe the same issue differently, and note which models raised each one. Findings two or more models raised independently are the highest signal. Read a lone model's finding, but weight it accordingly. Note disagreements. If one model flags something and another explicitly says the opposite, that is context for the verdict.

## Step 5, Lead Judgment

You are the lead reviewer, a pragmatic senior engineer, not a neutral aggregator. Read `references/lead-judgment.md` for the full framework. Put every finding in one of four buckets, with the model(s) that raised it and a one-line rationale.

- **Act on**. Real issues affecting correctness, security, or maintainability given the actual goals. They would block a real PR.
- **Consider**. Legitimate, but you're not sure they outweigh the cost of addressing them now. Worth the user's attention.
- **Noted**. Technically valid but not actionable. Context-dependent, premature optimization, or low-impact at this stage.
- **Dismissed**. Wrong, nitpicky, or missing context, with a brief reason.

## Output Format

### Intent
> [The stated intent paragraph from Step 2]

### Reviewers
- Reviewer [label]: [model name], [N findings] (one bullet per reviewer)

### Act On
[Each: description, which models raised it, why it matters.]

### Consider
[Each: description, which models raised it, the tradeoff.]

### Noted
[Brief list.]

### Dismissed
[Each with a brief rationale.]

### Agreement Map
[Where models agreed and diverged, and what that pattern tells us.]

## pstack on Claude Code

When you run this skill directly, `<pstack>` is `${CLAUDE_PLUGIN_ROOT}`, `<store>` is `${CLAUDE_PLUGIN_DATA}/store`, and this session's ID is `${CLAUDE_SESSION_ID}`. When poteto-mode, another pstack skill, or a brief sent you here, use the values it names. Other pstack skills named here (in bold, or as `principle-*`) live at `<pstack>/skills/<name>/SKILL.md`. They are user-invocable only, so Read them with the Read tool instead of the Skill tool. Per-role models come from `~/.claude/pstack-models.md` (see the **setup-pstack** skill). Cursor-specific terms, and a todolist in a session without a todo tool, map per `<pstack>/skills/poteto-mode/references/claude-code.md`.
