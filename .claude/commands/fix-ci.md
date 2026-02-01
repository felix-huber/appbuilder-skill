# /fix-ci — Automatically Fix Failing CI Tests

## Goal
Read CI failure logs and fix the issues automatically.

## Syntax
```
/fix-ci [run-id]
```

## Process

### 1. Get Failure Information

If run-id provided:
```bash
gh run view <run-id> --log-failed
```

Otherwise, get latest failed run:
```bash
gh run list --status failure --limit 1 --json databaseId,conclusion,headBranch
# Use databaseId from above
gh run view <run-id> --log-failed
```

### 2. Parse Failures

Extract from logs:
- Failed test names
- Error messages
- Stack traces
- File:line references

### 3. Categorize Issues

| Type | Detection | Action |
|------|-----------|--------|
| Test failure | `FAIL` + test name | Read test, read implementation, fix |
| Build error | `error TS` / `SyntaxError` | Fix syntax/type issue |
| Lint failure | `error` + rule name | Apply lint fix |
| Timeout | `exceeded` / `SIGTERM` | Investigate slow test |
| Flaky | Same test passes locally | Add retry or fix race condition |

### 4. Fix Each Issue

For each failure:
1. Read the failing file
2. Read related implementation
3. Determine root cause
4. Apply fix
5. Run the specific failing test locally to verify fix

### 5. Verify All Fixes

Run stack-appropriate verification:

| Stack | Command |
|-------|---------|
| Node.js | `npm run lint && npm run typecheck && npm run build && npm test` |
| Python | `ruff check . && mypy . && pytest -v` |
| Rust | `cargo clippy && cargo check && cargo test` |
| Go | `go vet ./... && go build ./... && go test ./...` |
| Makefile | `make lint && make build && make test` |

### 6. Report

```
╔═══════════════════════════════════════════════════════════════╗
║                    CI FIXES APPLIED                           ║
╠═══════════════════════════════════════════════════════════════╣
║  Failures found:  3                                           ║
║  Fixed:           3                                           ║
║  Verification:    PASSED                                      ║
╚═══════════════════════════════════════════════════════════════╝

Fixed:
- test/query-builder.test.ts: Fixed null check in result handler
- src/components/Table.tsx: Added missing key prop
- src/utils/format.ts: Fixed off-by-one in pagination
```

## Examples

### Fix Latest Failure
```
/fix-ci
```

### Fix Specific Run
```
/fix-ci 12345678
```

## Integration

Works well with:
```bash
# After fixing, push and verify
git add -A && git commit -m "fix: resolve CI failures" && git push

# Watch CI
gh run watch
```

## Prerequisites

- `gh` CLI installed and authenticated
- Repository has GitHub Actions configured
