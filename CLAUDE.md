# Claude Code Instructions — Oracle Swarm Extension

## When Working With Me

- Be concise, skip obvious explanations
- Just make the fix, don't ask permission for small/obvious changes (see Plan Mode below)
- If something's unclear, make a reasonable assumption and note it
- When given a bug report: first write a test that reproduces the bug. Then fix it and prove it with a passing test.
- Be resourceful before asking. Read the file. Check context. Search for it. Come back with answers, not questions.

---

## Plan Mode

Enter plan mode for non-trivial tasks (3+ steps, architectural decisions, multiple files, unclear requirements).

1. Write plan to `tasks/todo.md`
2. Get user approval before implementing
3. Track progress by checking off items
4. If things go sideways: STOP, document in `tasks/lessons.md`, re-plan

---

## Rules

### Rule 1: Never Delete Files Without Permission
Ask first, always. Even files you created.

### Rule 2: No File Proliferation
Revise existing files. Never create `file_v2.js`, `file_improved.js`, etc.

### Rule 3: No Automated Code Transforms
Make changes manually. Use subagents in parallel for many simple changes.

### Rule 4: Simplicity
> "Would a senior engineer say this is overcomplicated? If yes, simplify."

### Rule 5: No Laziness
Find root causes. No temporary fixes. Minimal impact.

---

## Non-negotiables

1. **Browser Oracle only** — Never API mode
2. **Artifacts are truth** — Update `artifacts/` before code
3. **No evidence = not done** — Show commands + outputs
4. **Task graph is truth** — Explicit dependencies via beads or task-graph.json
5. **Iterate until convergence** — Reviews run multiple times (see iteration table)
6. **Backpressure required** — Tasks must have verification

## Iteration Requirements

| Phase | Minimum |
|-------|---------|
| Plan review (Oracle) | 4-5 passes |
| Beads review | 6-9 passes |
| Code review | Until 0 bugs |
| Oracle review | Until 0 blockers/majors |

**DO NOT SKIP ITERATIONS.**

---

## For Codex/GPT-5.2

Before modifying files, re-read them:
```bash
git status && git log --oneline -5
```
Another agent may have changed things.

---

## SAFETY Comment Convention

When lint rules must be bypassed for valid reasons, use SAFETY comments:

```python
# SAFETY: Singleton pattern - intentional shared state for caching
def get_config(config_cache=[None]):
    if config_cache[0] is None:
        config_cache[0] = load_config_from_disk()
    return config_cache[0]
```

**Tiers:**
- **CRITICAL** (secrets, SQL injection, shell injection): Cannot bypass, ever
- **SECURITY**: Requires `SAFETY(TICKET-123)` + human code review
- **QUALITY**: Allows `SAFETY: explanation` (e.g., mutable defaults, unwrap)
- **STYLE**: Info only, no bypass needed

---

## Context Priming

At session start, run `/context prime` to load project context. This loads:
- `.claude/context/*.md` — Project overview, tech stack, structure, status
- `CLAUDE.md` — Agent instructions
- `tasks/lessons.md` — Patterns to avoid
- Last 20 lines of `progress.txt` — Recent activity

---

## Self-Improvement

After corrections from user:
1. Update `tasks/lessons.md` with pattern
2. Consider promoting to CLAUDE.md if recurring

At session start:
1. Run `/context prime` to load project context
2. Check `tasks/todo.md` for incomplete work
3. Read `tasks/lessons.md`