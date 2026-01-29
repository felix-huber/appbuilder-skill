---
name: devin-review
description: Free AI code review for GitHub PRs. Detects bugs, groups changes logically, and provides context-aware feedback.
---

# Devin Review Integration

Devin Review is a **free** AI code review tool that provides:
- **Bug detection** with severity levels (severe/non-severe)
- **Logical code grouping** (not alphabetical)
- **Copy/move detection** (avoids false "full delete + insert")
- **Context-aware Q&A** about the codebase

## When to Use

1. **After all tasks complete** (Ralph auto-triggers this)
2. **Before merging any PR**
3. **During code review**

## Quick Start

### Option 1: URL Transform (Fastest)

Change `github.com` to `devin.ai` in any PR URL:

```
github.com/owner/repo/pull/123
    ↓
devin.ai/owner/repo/pull/123
```

### Option 2: Web App

1. Go to https://app.devin.ai/review
2. Paste your PR URL
3. Wait for analysis

### Option 3: Script (Saves Feedback)

```bash
./scripts/devin_review.sh <pr_number>
./scripts/devin_review.sh 123
./scripts/devin_review.sh https://github.com/owner/repo/pull/123
```

### Option 4: CLI (For Private Repos)

```bash
npx devin-review
```

## Understanding Results

### Bugs (Fix These!)

Bugs are actionable errors with confidence levels:

| Severity | Action |
|----------|--------|
| **Severe** | 🔴 Fix immediately before merge |
| **Non-severe** | 🟡 Review and fix if valid |

### Flags (Investigate)

| Type | Action |
|------|--------|
| **Investigate** | ⚠️ Review the code, may be a bug |
| **Informational** | ℹ️ Explains how something works |

## Integration with Ralph

Ralph auto-triggers Devin Review when all tasks complete:

```bash
./scripts/ralph.sh 50

# After completion:
# ✅ All tasks complete!
# 🔍 Opening Devin Review...
# Fix any SEVERE bugs before merging.
```

To disable auto-review:
```bash
DEVIN_REVIEW=false ./scripts/ralph.sh 50
```

## Workflow

```
                    ┌─────────────────┐
                    │  Code Complete  │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  Create PR      │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
     ┌────────▼────────┐ ┌───▼───┐ ┌───────▼───────┐
     │  Human Review   │ │ Devin │ │ Oracle (code) │
     └────────┬────────┘ └───┬───┘ └───────┬───────┘
              │              │              │
              └──────────────┼──────────────┘
                             │
                    ┌────────▼────────┐
                    │  Fix Issues     │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │     Merge       │
                    └─────────────────┘
```

## Feeding Feedback to Claude Code

After saving Devin feedback:

```
Read artifacts/06-oracle/devin/pr-123-review.md and fix all bugs found.
Use fresh eyes review after each fix.
```

Or use the review command:

```bash
/review code  # Fresh eyes review with Devin context
```

## Best Practices

1. **Always run Devin Review** before merging
2. **Fix all SEVERE bugs** - these are high-confidence issues
3. **Investigate flags** - they may reveal edge cases
4. **Save feedback** to artifacts for tracking

## Limitations

- Free for public repos only (private repos need Devin account)
- Does not auto-fix code (you apply the fixes)
- 5-10 minute analysis time

## Resources

- Web App: https://app.devin.ai/review
- Docs: https://docs.devin.ai/work-with-devin/devin-review
- CLI: `npx devin-review`
