# /context — Context Management

## Goal
Manage project context for AI agent sessions. Context priming ensures agents start informed.

## Subcommands

| Command | Purpose |
|---------|---------|
| `/context` | Interactive menu |
| `/context prime` | Load context into current session |
| `/context create` | Analyze codebase and create context files |
| `/context update` | Refresh context with recent changes |
| `/context diagnose` | Show what's loaded and why |

---

## /context prime

**Use at session start.** Loads all context files to prime the agent.

### What It Does

1. Reads `.appbuilder.yaml` for context configuration
2. Loads each file in `.claude/context/`:
   - `project-overview.md` — What this project is
   - `tech-context.md` — Stack, dependencies, patterns
   - `project-structure.md` — File organization
   - `status.md` — Current progress and pending work
3. Also loads:
   - `CLAUDE.md` — Agent instructions
   - `tasks/lessons.md` — Patterns to avoid
   - Last 20 lines of `progress.txt` — Recent activity

### Usage

```bash
/context prime
```

### Output

```
✅ Context primed (4 files, 12KB total)

Project: AppBuilder Skill
Status: Implementing v2 proposal
Recent lessons: 3 patterns loaded
```

---

## /context create

**Run once per project.** Analyzes codebase and creates context files.

### What It Does

1. Scans project structure
2. Reads `package.json`, `Cargo.toml`, `go.mod`, etc. for dependencies
3. Identifies architectural patterns
4. Creates `.claude/context/` files with findings

### Usage

```bash
/context create
```

### Accuracy Requirements

When creating context, follow these rules:
- Only document patterns you can point to in actual code
- Mark assumptions with: `⚠️ Assumption: [claim]`
- Don't invent APIs or patterns that don't exist
- Include file references for every technical claim

---

## /context update

**Run periodically.** Refreshes context with recent changes.

### What It Does

1. Checks git log for recent changes
2. Updates `status.md` with current state
3. Adds new patterns discovered
4. Preserves existing accurate context

### Usage

```bash
/context update
```

---

## /context diagnose

**Debug context issues.** Shows what's loaded and validates accuracy.

### What It Does

1. Lists all context files and their sizes
2. Checks for stale content (older than 7 days)
3. Validates references (do mentioned files exist?)
4. Reports total context size vs. limit

### Usage

```bash
/context diagnose
```

### Output

```
Context Diagnosis
=================

Files:
  ✅ project-overview.md (2.1KB, updated 2h ago)
  ✅ tech-context.md (1.8KB, updated 2h ago)
  ⚠️ status.md (0.5KB, updated 7d ago) — STALE
  ✅ project-structure.md (1.2KB, updated 2h ago)

Total: 5.6KB / 200KB limit (2.8%)

Validation:
  ✅ All file references exist
  ⚠️ 1 stale file needs update

Recommendation: Run /context update
```

---

## Configuration

In `.appbuilder.yaml`:

```yaml
context:
  enabled: true
  auto_prime: true        # Auto-load on session start
  max_size_kb: 200        # Prevent context overflow
  files:
    - .claude/context/project-overview.md
    - .claude/context/tech-context.md
    - .claude/context/project-structure.md
    - .claude/context/status.md
```

---

## Best Practices

1. **Run `/context prime` at session start** — Instant context vs. re-discovering
2. **Run `/context update` after major changes** — Keep context accurate
3. **Run `/context diagnose` if agents seem confused** — Find stale context
4. **Keep context under 200KB** — Larger contexts reduce quality
