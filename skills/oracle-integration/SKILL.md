---
name: oracle-integration
description: Provides Oracle CLI integration for GPT-5.2 Pro review loops. Use when running external model reviews, multi-model consensus, or structured issue extraction from Oracle outputs.
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

Integrate GPT-5.2 Pro reviews into your development workflow via the Oracle CLI.

## Overview

Oracle bundles your artifacts and runs them through GPT-5.2 Pro (browser mode) with specialized review lenses. This skill guides the integration process.

## Key Principles

1. **Browser mode only**: Oracle runs use your ChatGPT session, not API (cheaper, fully automated)
2. **8 specialized lenses**: product, ux, architecture, security, performance, tests, simplicity, ops
3. **Structured output**: All reviews produce normalized `issues.json` with consistent schema
4. **Fully autonomous**: Run Oracle scripts directly - DO NOT ask user to run commands

---

## ⚠️ MANDATORY FIRST STEP — CHECK EXISTING STATE ⚠️

**BEFORE running any Oracle script, ALWAYS check what already exists:**

```bash
# 1. What Oracle output exists?
ls -la artifacts/06-oracle/<kind>/ 2>/dev/null || echo "No Oracle output yet"

# 2. Convergence state?
cat artifacts/06-oracle/<kind>/convergence-history.json 2>/dev/null || echo "No history"

# 3. Latest feedback files?
ls -t artifacts/06-oracle/<kind>/*.md 2>/dev/null | head -3
```

**Decision tree:**

| Check Result | Action |
|--------------|--------|
| No Oracle output | → Run Oracle |
| Converged (0 blockers, ≤2 majors) | → **DONE!** No action needed |
| Unapplied feedback exists | → **Apply feedback first**, then reassess |
| Applied but not converged | → Run another Oracle round |

**How to tell if feedback is unapplied:**
- Oracle files newer than artifact
- Issues in Oracle output still visible in artifact

---

## STEP 1: Run Oracle (only if needed per above)

**DO NOT ask the user to run commands.** Execute directly:

```bash
# Run this directly - DO NOT print and ask user to run
./scripts/oracle_converge.sh ux artifacts/02-ux.md artifacts/01-prd.md
```

**This takes 60-90 minutes.** The script:
1. Calls GPT-5.2 Pro via browser automation
2. GPT-5.2 Pro has extended thinking (30-60 min silence is normal)
3. Returns structured feedback
4. Loops until convergence (0 blockers, ≤2 majors)

## Oracle CLI Reference

### Full Lens Pack
Run all 8 lenses for a phase:
```bash
./scripts/oracle_lens_pack.sh <kind> <files...>
```

| Kind | Primary File | Context Files |
|------|--------------|---------------|
| prd | artifacts/01-prd.md | artifacts/00-brief.md |
| ux | artifacts/02-ux.md | artifacts/01-prd.md |
| plan | artifacts/03-plan.md | artifacts/01-prd.md, artifacts/02-ux.md |
| code | (specific files) | artifacts/03-plan.md |

### Single Lens
Run one specific lens:
```bash
./scripts/oracle_single_lens.sh <kind> <lens> <files...>
```

Lenses: `product`, `ux`, `architecture`, `security`, `performance`, `tests`, `simplicity`, `ops`

### Fallback (Manual Paste)
If browser automation fails:
```bash
npx -y @steipete/oracle --render --copy-markdown \
  --engine browser \
  --browser-manual-login \
  --browser-no-cookie-sync \
  --model gpt-5.2-pro \
  --prompt "$(cat prompts/<kind>/<lens>.txt)" \
  --file "<files...>"
```

Then paste into ChatGPT (GPT-5.2 Pro) and save response to:
`artifacts/06-oracle/<kind>/<timestamp>_<lens>.md`

## Issue Schema

All issues follow this structure:
```json
{
  "id": "abc123",
  "severity": "blocker|major|minor|nit",
  "category": "product|ux|arch|security|perf|tests|simplicity|ops",
  "title": "Short description",
  "evidence": "Quote or reference from artifact",
  "recommendation": "Concrete change to make",
  "acceptanceTest": "How to verify the fix",
  "files": ["optional/affected/paths.ts"]
}
```

## When to Use Oracle

| Situation | Action |
|-----------|--------|
| PRD complete, before UX | `/oracle prd` |
| UX complete, before plan | `/oracle ux` |
| Plan complete, before coding | `/oracle plan` |
| Code complete, before gates | `/oracle code` |
| Stuck on decision | Run specific lens for perspective |
| Want second opinion | Run oracle on any artifact |

## Integration with Compound Engineering

Oracle complements Compound Engineering's Claude-native review:

```
┌─── Compound Engineering ───┐   ┌─── Oracle Extension ───┐
│ /workflows:review          │   │ /oracle code           │
│ 13 Claude agents parallel  │ + │ GPT-5.2 Pro external   │
│ (security-sentinel, etc.)  │   │ (fresh perspective)    │
└────────────────────────────┘   └────────────────────────┘
```

## Troubleshooting

### Browser automation fails
1. **Keep Chromium window OPEN** during Oracle runs
2. Use `--browser-manual-login` (now default in Oracle Swarm)
3. Log into ChatGPT in the Chromium window that opens
4. Close other ChatGPT tabs

### Setup: Persistent Chromium Profile (Recommended)

Create `~/.oracle/config.json`:
```json
{
  "browser": {
    "manualLogin": true,
    "noCookieSync": true,
    "chromePath": "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "chromeProfile": null
  }
}
```

This:
- Uses persistent profile at `~/.oracle/browser-profile`
- No cookie sync (no Keychain prompts!)
- Log in once, reuse forever

### Issues not parsing
1. Check Oracle output for valid JSON in code fence
2. Run normalizer manually:
   ```bash
   node scripts/normalize_oracle_output.js <dir> <out.json>
   ```

### Too many issues
1. Focus on blockers and majors first
2. Use single lens for specific concerns
3. Increase issue quality by improving artifacts
