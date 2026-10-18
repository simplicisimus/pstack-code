---
name: arena
description: "Spawn N parallel candidates at the same task, pick a base, graft the strongest parts of the losers into it. Use for /arena, 'arena this', 'throw it in the arena', or when one attempt at a non-trivial artifact would lock in the wrong shape."
argument-hint: "[task]"
disable-model-invocation: true
---

# Arena

Open a todolist with one entry per phase (Frame, Fan out, Cross-judge, Pick, Graft, Verify) before launching anything.

## Phase A: Frame

Every candidate gets the same prompt, so the prompt is the contract.

1. State the artifact each candidate is producing.
2. Derive the rubric, 3-6 concrete gradeable criteria for what success looks like on *this* task. It is the picker's tool in Phase D. Candidates only see the task.
3. Pick the runners. Use the `arena runners` line in `~/.claude/pstack-models.md`. If the rule or that line is missing, default to one each on `opus` and `sonnet`. Resolve the line with `pstack-role --seat write --panel --default 'opus, sonnet' 'arena runners'` when the runners write code, or `--seat review --panel` when their artifact is a document. Resolve the cross-judge pool below as a review seat without `--panel`, since the pool yields one judge. `pstack-role` applies the value grammar in the **setup-pstack** skill and prints one line per seat with its `subagent_type`, its `model` when one applies, and the brief of a bridge seat. A runner whose artifact is code is a write seat: spawn it with `isolation: "worktree"`, and a `codex:` or `grok:` runner gets `Mode: write`, so its worktree is its output path. A runner whose artifact is a document is a review seat: a `codex:` or `grok:` runner gets `Mode: review`, runs from the parent when you start it from the main conversation (see the Bridge brief in the **setup-pstack** skill), and you copy its answer file to its output path. An `openrouter:` runner returns its artifact as text, and you write it to its output path. If a configured entry fails to spawn or a bridge replies `FAILED`, run that seat on `opus` and say so. A disabled alias drops its seat instead. Spawn more runners when the arena covers multiple design directions. Use the same model N times when the work is generation-bound rather than judgment-sensitive. Pick each subagent's effort for the job, per the Subagents section of the **poteto-mode** skill.
4. Give each candidate its own output location (a git worktree where possible, otherwise `/tmp/arena-<slug>/candidate-<n>/`), per the **separate-before-serializing-shared-state** principle skill.

## Phase B: Fan out

Start all N candidates in one message with `run_in_background: true`, each with the task, the path to the shared grounding, its own output path, and instructions to produce the artifact and a short rationale naming the alternatives it considered and what it rejected.

If a candidate produces no output, proceed with N-1 and note the dropout.

## Phase C: Cross-judge

After all Phase B candidates complete, choose one model from the `arena cross-judge pool` line in `~/.claude/pstack-models.md`. If the rule or that line is missing, choose from `opus`, `sonnet`. Prefer an entry that differs from the parent's model. A `codex:`, `grok:`, or `openrouter:` entry (or an `agent:` backed by a non-Claude model) is the strongest choice when the pool has one. With a Claude-only pool, the judge's fresh context is the main source of independence. Spawn one judge on that model as a review seat: `pstack-code:reviewer` for a Claude model, `Mode: review` for a bridge. It sees the rubric and the candidates by path label, scores each criterion, and recommends a base with rationale. It runs in parallel with your reading in Phase D. Don't spawn it while candidates are still writing.

## Phase D: Pick a base

Read every candidate end to end before picking. Score each against the rubric criterion by criterion, not on holistic feel, and compare with the cross-judge. Agreement on the base confirms the pick. Disagreement means one of you is biased or the rubric was ambiguous. Read both rationales before deciding.

Pick the base a future maintainer can extend most easily without breaking invariants. When two feel tied, prefer the cleaner boundary or smaller API, per the Laziness Protocol.

## Phase E: Graft

Walk each losing candidate once more for what is worth porting into the base, usually one or two things per candidate, not most of it. Fold each graft in by hand, per the **redesign-from-first-principles** principle skill, so the result stays coherent under one mental model. Don't paste mechanically.

If the candidates converge on one shape, that is strong agreement. Note it and ship the consensus shape. No graft is needed. If they wildly diverge, Phase A was under-specified. Reframe and re-run rather than averaging the divergence.

## Phase F: Verify

Verify the synthesized artifact like any other output, per the **prove-it-works** principle skill. If verification finds a problem the arena missed, either Phase A was wrong (re-frame and re-run) or a candidate caught it and you missed the graft (go back to Phase E). Don't paper over it.

## Outputs

One synthesized artifact, with a short synthesis note alongside naming the base and why, the cross-judge's verdict, each graft with its source candidate, what was rejected and why, any convergence or dropouts, and the verification result.

## pstack on Claude Code

When you run this skill directly, `<pstack>` is `${CLAUDE_PLUGIN_ROOT}`, `<store>` is `${CLAUDE_PLUGIN_DATA}/store`, and this session's ID is `${CLAUDE_SESSION_ID}`. When poteto-mode, another pstack skill, or a brief sent you here, use the values it names. Other pstack skills named here (in bold, or as `principle-*`) live at `<pstack>/skills/<name>/SKILL.md`. They are user-invocable only, so Read them with the Read tool instead of the Skill tool. Per-role models come from `~/.claude/pstack-models.md` (see the **setup-pstack** skill). Cursor-specific terms, and a todolist in a session without a todo tool, map per `<pstack>/skills/poteto-mode/references/claude-code.md`.
