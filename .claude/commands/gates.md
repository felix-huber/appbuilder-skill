# /gates — Run Verification Gates

## Goal
Run all verification checks and generate a verification report.

## Prerequisites
- Code implementation should be complete (or at checkpoint)
- `artifacts/03-plan.md` exists (for verification plan)

## Output
- `artifacts/07-verification.md`

## Steps

### 1. Run gate pack script
```bash
bash scripts/gate_pack.sh
```

### 2. If script doesn't exist or needs customization

Run checks manually and capture results:

#### Lint Check
```bash
npm run lint 2>&1 | tee /tmp/lint.log
LINT_EXIT=$?
```

#### Type Check
```bash
npm run typecheck 2>&1 | tee /tmp/types.log
# or: tsc --noEmit
TYPES_EXIT=$?
```

#### Unit Tests
```bash
npm run test 2>&1 | tee /tmp/unit.log
UNIT_EXIT=$?
```

#### E2E Tests (if configured)
```bash
npm run test:e2e 2>&1 | tee /tmp/e2e.log
E2E_EXIT=$?
```

#### E2E Happy Path Tests (if configured)
```bash
if [ -f scripts/run_e2e_happy_paths.sh ]; then
  chmod +x scripts/run_e2e_happy_paths.sh
  ./scripts/run_e2e_happy_paths.sh 2>&1 | tee /tmp/e2e.log
  E2E_EXIT=$?
else
  echo "⚠️ No E2E tests (scripts/run_e2e_happy_paths.sh not found)"
  E2E_EXIT=0
fi
```

#### Build Check
```bash
npm run build 2>&1 | tee /tmp/build.log
BUILD_EXIT=$?
```

#### Bundle Size (optional)
```bash
du -sh dist/ 2>/dev/null || echo "N/A"
```

### 3. Generate verification report

Create `artifacts/07-verification.md`:

````markdown
# 07 — Verification Report

Generated: [timestamp]

## Summary

| Gate | Status | Details |
|------|--------|---------|
| Lint | ✅ PASS | 0 errors, 3 warnings |
| Types | ✅ PASS | No type errors |
| Unit Tests | ✅ PASS | 47/47 passed |
| E2E Tests | ⚠️ PARTIAL | 8/10 passed, 2 skipped |
| Build | ✅ PASS | Built in 4.2s |
| Bundle Size | ✅ PASS | 245 KB (limit: 500 KB) |

**Overall: ✅ READY FOR REVIEW**

## Lint Results

```
[paste lint output]
```

### Warnings to Address
- Warning 1: …
- Warning 2: …

## Type Check Results

```
[paste typecheck output]
```

## Unit Test Results

```
[paste test output summary]
```

### Test Coverage
- Statements: 78%
- Branches: 65%
- Functions: 82%
- Lines: 77%

## E2E Test Results

```
[paste e2e output summary]
```

### Skipped Tests
- `test-name.spec.ts`: Reason for skip

### Failed Tests (if any)
- None

## Build Results

```
[paste build output]
```

### Bundle Analysis
- Total size: 245 KB
- Main chunk: 180 KB
- Vendor chunk: 65 KB

## Manual Verification Checklist

From `artifacts/03-plan.md` verification plan:

- [ ] User can [primary action]
- [ ] User can [secondary action]
- [ ] Error states display correctly
- [ ] Data persists across reload
- [ ] Responsive on mobile
- [ ] Keyboard navigation works
- [ ] No console errors

## Regression Checklist

- [x] All unit tests pass
- [x] All E2E tests pass (with noted skips)
- [ ] No console errors — **CHECK MANUALLY**
- [ ] Lighthouse score > 90 — **NOT CHECKED**
- [x] Bundle size < 500 KB

## Blockers for Release

- None

## Recommendations

1. Fix lint warning about unused import in `src/utils.ts`
2. Increase test coverage for error handling paths
3. Run Lighthouse audit before release
````

### 4. Determine gate status

| Condition | Status |
|-----------|--------|
| All gates pass | ✅ READY FOR REVIEW |
| Warnings only | ⚠️ READY WITH WARNINGS |
| Any failure | ❌ NOT READY |

### 5. Next action based on status

**If READY (all gates pass):**
- Auto-run `/ship` to create release plan

**If WARNINGS:**
- Review `artifacts/07-verification.md`
- Ask user: "Proceed with warnings? (y/n)"
- If yes, auto-run `/ship`

**If NOT READY:**
- Report failures from `artifacts/07-verification.md`
- Fix issues and re-run `/gates`

## Customization

Edit `scripts/gate_pack.sh` for your stack:
- Add/remove checks
- Adjust thresholds
- Add custom gates (security scan, license check, etc.)
