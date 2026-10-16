---
name: sharpen
description: "Sharpen a task before starting: the expert approach, what the user is really after, and the right level of specification. Use for /sharpen."
argument-hint: "[task]"
disable-model-invocation: true
---

Before starting, ask how a top expert would approach this task (their raw sources, their real methods, an outside check that the result is right), what the user is really after, and whether the task is over- or underspecified. Loosen constraints that don't serve the goal as readily as you add ones that do, and leave choices that are the user's to make open instead of deciding them. Fold in only what makes the work better, not bigger, but always keep one outside check that the result is right, without narrating the framing, then do the work. Don't hand back a rewritten prompt.

## pstack on Claude Code

When you run this skill directly, `<pstack>` is `${CLAUDE_PLUGIN_ROOT}`, `<store>` is `${CLAUDE_PLUGIN_DATA}/store`, and this session's ID is `${CLAUDE_SESSION_ID}`. When poteto-mode, another pstack skill, or a brief sent you here, use the values it names. Other pstack skills named here (in bold, or as `principle-*`) live at `<pstack>/skills/<name>/SKILL.md`. They are user-invocable only, so Read them with the Read tool instead of the Skill tool. Per-role models come from `~/.claude/pstack-models.md` (see the **setup-pstack** skill). Cursor-specific terms, and a todolist in a session without a todo tool, map per `<pstack>/skills/poteto-mode/references/claude-code.md`.
