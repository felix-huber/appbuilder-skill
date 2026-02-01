---
name: oracle-integration
description: Oracle CLI integration for GPT-5.2 Pro review loops. Runs external model reviews with structured issue extraction.
triggers:
  - oracle review
  - gpt-5 review
  - external review
  - multi-model
  - second opinion
  - oracle lens
  - browser oracle
---

# Oracle Integration Skill

GPT-5.2 Pro reviews via browser automation. Bundles artifacts, runs specialized lenses, outputs structured issues.

## Key Facts

- **Browser mode only** - uses your ChatGPT session, not API
- **8 lenses** - product, ux, architecture, security, performance, tests, simplicity, ops
- **Per-lens convergence** - each lens tracked in `convergence-${LENS}.json`
- **Auto-resume** - script continues from last round if interrupted

---

## Before Running: Check Existing State

```bash
# What exists?
ls -la artifacts/06-oracle/<kind>/ 2>/dev/null

# Per-lens convergence state?
cat artifacts/06-oracle/<kind>/convergence-product.json 2>/dev/null

# Latest outputs?
ls -t artifacts/06-oracle/<kind>/*.md 2>/dev/null | head -3
```

**Decision:**
| State | Action |
|-------|--------|
| No output | Run Oracle |
| Lens converged (0 blockers/majors) | Skip that lens |
| Unapplied feedback | Apply first, then reassess |
| Partially converged | Script auto-resumes |

---

## Running Oracle

### oracle_converge.sh (Primary)

**Interactive (default):**
```bash
./scripts/oracle_converge.sh prd artifacts/01-prd.md artifacts/00-brief.md
```
Shows menu:
```
[1] QUICK MODE - Product lens only
    Time: ~1-2 hours

[2] FULL MODE - All 8 lenses with convergence
    Time: ~4-16 hours (overnight recommended)

[3] SINGLE LENS - Choose one specific lens
    Time: ~30-90 min per convergence round
```

**Non-interactive flags:**
```bash
# Quick: product lens only
./scripts/oracle_converge.sh --quick prd artifacts/01-prd.md

# Full: all 8 lenses
./scripts/oracle_converge.sh --all prd artifacts/01-prd.md

# Single specific lens
./scripts/oracle_converge.sh --lens architecture prd artifacts/01-prd.md
```

**Time estimates:**
| Mode | Flag | Time | Use Case |
|------|------|------|----------|
| Quick | `--quick` | 1-2 hrs | Fast iteration, early drafts |
| Full | `--all` | 4-16 hrs | Final review before implementation |
| Single | `--lens X` | 30-90 min/round | Targeted review |

**Environment:**
- `MAX_ROUNDS=10` - max iterations per lens (default: 10)

### Output Files

```
artifacts/06-oracle/<kind>/
  convergence-product.json      # Per-lens history
  convergence-architecture.json
  issues-product.json           # Final issues for lens
  issues-architecture.json
  issues.json                   # Merged all-lens issues
  20250201_143052_product.md    # Raw Oracle output
```

Per-lens history format:
```json
{
  "lens": "product",
  "rounds": [
    {"round": 1, "blockers": 2, "majors": 1, "minors": 3, "nits": 5, "suggestions": 4, "confidence": 6},
    {"round": 2, "blockers": 0, "majors": 0, "minors": 2, "nits": 4, "suggestions": 3, "confidence": 8}
  ]
}
```

### oracle_lens_pack.sh (Single Pass)

All 8 lenses once, no convergence loop:
```bash
./scripts/oracle_lens_pack.sh <kind> <files...>
```
Use for quick baseline scan without iterating.

### oracle_single_lens.sh (No Convergence)

One lens, one pass:
```bash
./scripts/oracle_single_lens.sh <kind> <lens> <files...>
```

---

## Issue Schema

```json
{
  "id": "abc123",
  "severity": "blocker|major|minor|nit",
  "category": "product|ux|arch|security|perf|tests|simplicity|ops",
  "title": "Short description",
  "evidence": "Quote from artifact",
  "recommendation": "Concrete change",
  "acceptanceTest": "How to verify fix",
  "files": ["optional/paths.ts"]
}
```

---

## When to Use

| Stage | Command |
|-------|---------|
| PRD done, before UX | `./scripts/oracle_converge.sh prd ...` |
| UX done, before plan | `./scripts/oracle_converge.sh ux ...` |
| Plan done, before coding | `./scripts/oracle_converge.sh plan ...` |
| Code done, before gates | `./scripts/oracle_converge.sh code ...` |
| Targeted review | `./scripts/oracle_converge.sh --lens <lens> ...` |

---

## Troubleshooting

**Browser automation fails:**
1. Keep Chromium window open during runs
2. Log into ChatGPT in the Chromium window
3. Close other ChatGPT tabs
4. Script retries 3 times before manual fallback

**Setup persistent profile** (`~/.oracle/config.json`):
```json
{
  "browser": {
    "manualLogin": true,
    "noCookieSync": true,
    "chromePath": "/Applications/Chromium.app/Contents/MacOS/Chromium"
  }
}
```

**Issues not parsing:**
```bash
node scripts/normalize_oracle_output.js <dir> <out.json>
```

**Too many issues:** Focus on blockers/majors first. Use `--lens` for specific concerns.
