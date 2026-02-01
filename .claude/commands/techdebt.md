# /techdebt — Find and Report Technical Debt

## Goal
End-of-session scan to identify and optionally fix technical debt.

## Syntax
```
/techdebt [--fix] [--scope <path>]
```

## Process

### 1. Scan for Debt Indicators

#### TODO/FIXME Comments
```bash
# Default scans src/, use --scope to override
grep -rn "TODO\|FIXME\|HACK\|XXX\|TEMP\|WORKAROUND" ${SCOPE:-src/} --include="*.ts" --include="*.tsx" --include="*.js" --include="*.py" --include="*.rs" --include="*.go"
```

#### Duplicated Code
Look for:
- Similar function bodies (>10 lines)
- Copy-pasted logic with minor variations
- Multiple implementations of same pattern

#### Unused Exports
```bash
# Find exports in scope
grep -rh "^export" ${SCOPE:-src/} --include="*.ts" --include="*.js" | sort | uniq

# Check if each is imported elsewhere
```

#### Dead Code
- Functions never called
- Commented-out code blocks
- Unreachable branches

#### Complexity Hotspots
- Functions > 50 lines
- Files > 500 lines
- Deeply nested logic (>4 levels)
- High cyclomatic complexity

#### Dependency Issues
- Outdated packages (major versions behind)
- Unused dependencies
- Missing peer dependencies

### 2. Categorize by Severity

| Severity | Description | Example |
|----------|-------------|---------|
| P1 | Blocking future work | Duplicated core logic |
| P2 | Maintenance burden | TODO with no context |
| P3 | Code smell | Long function |
| P4 | Nice to have | Minor refactor opportunity |

### 3. Generate Report

```markdown
# Technical Debt Report

Generated: 2026-02-01

## Summary
- P1 (Critical): 2
- P2 (Major): 5
- P3 (Minor): 12
- P4 (Trivial): 8

## P1: Critical

### Duplicated validation logic
- `src/components/Form.tsx:45-67`
- `src/components/Modal.tsx:23-45`
**Recommendation:** Extract to `src/utils/validation.ts`

### Missing error boundary
- `src/App.tsx` has no error boundary
**Recommendation:** Add ErrorBoundary component

## P2: Major

### TODO: Implement caching (3 months old)
- `src/api/client.ts:123`
**Context:** Performance issue reported in #456

...
```

### 4. Optional Auto-Fix

With `--fix` flag:
1. Create branch `chore/techdebt-cleanup`
2. Fix P1 and P2 issues
3. Run verification
4. Create PR

## Examples

### Quick Scan
```
/techdebt
```
Output: Report only, no changes.

### Scan Specific Directory
```
/techdebt --scope src/components
```

### Scan and Fix
```
/techdebt --fix
```
Fixes P1/P2 issues automatically.

## Report Location

Saves to: `artifacts/techdebt-report.md`

## Integration with Workflow

Run at end of each session:
```
/techdebt
```

Run before major releases:
```
/techdebt --fix
/gates
```

## What This Does NOT Do

- Rewrite working code for style preferences
- Add abstraction layers "just in case"
- Refactor stable code without clear benefit

Focus is on **actionable debt** that causes real problems.
