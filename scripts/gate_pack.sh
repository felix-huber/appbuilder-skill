#!/usr/bin/env bash
set -euo pipefail

# Gate Pack Runner
# Runs verification gates and generates a report.
#
# Usage:
#   ./scripts/gate_pack.sh
#
# Customize this script for your stack.

OUT_FILE="artifacts/07-verification.md"
mkdir -p "$(dirname "$OUT_FILE")"

# Portable ISO timestamp (macOS date doesn't support -Iseconds)
iso_now() {
  if date -Iseconds >/dev/null 2>&1; then
    date -Iseconds
  else
    # macOS/BSD fallback
    date -u "+%Y-%m-%dT%H:%M:%SZ"
  fi
}

# Check if npm script exists
has_npm_script() {
  local script="$1"
  [[ -f "package.json" ]] || return 1
  command -v node &>/dev/null || return 1
  node -e 'const p=require("./package.json"); const s=process.argv[1]; process.exit(((p.scripts||{})[s])?0:1)' "$script" 2>/dev/null
}

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                    RUNNING GATES                              ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# Initialize report
{
  echo "# 07 — Verification Report"
  echo ""
  echo "Generated: $(iso_now)"
  echo ""
  echo "## Summary"
  echo ""
  echo "| Gate | Status | Details |"
  echo "|------|--------|---------|"
} > "$OUT_FILE"

OVERALL_STATUS="PASS"
RAN_ANY=0

# Initialize output variables
LINT_OUTPUT=""
TYPES_OUTPUT=""
TEST_OUTPUT=""
E2E_OUTPUT=""
BUILD_OUTPUT=""

# Gate: Lint
echo "━━━ Running lint..."
if has_npm_script "lint"; then
  RAN_ANY=1
  set +e
  LINT_OUTPUT=$(npm run lint 2>&1)
  LINT_EXIT=$?
  set -e

  if [[ $LINT_EXIT -eq 0 ]]; then
    echo "| Lint | ✅ PASS | No errors |" >> "$OUT_FILE"
    echo "✅ Lint passed"
  else
    LINT_ERRORS=$(echo "$LINT_OUTPUT" | grep -ciE "error|npm ERR!" || true)
    LINT_WARNINGS=$(echo "$LINT_OUTPUT" | grep -ci "warning" || true)
    if [[ $LINT_ERRORS -gt 0 ]]; then
      echo "| Lint | ❌ FAIL | $LINT_ERRORS errors, $LINT_WARNINGS warnings |" >> "$OUT_FILE"
      OVERALL_STATUS="FAIL"
      echo "❌ Lint failed"
    else
      echo "| Lint | ⚠️ WARN | $LINT_WARNINGS warnings |" >> "$OUT_FILE"
      echo "⚠️ Lint passed with warnings"
    fi
  fi
else
  echo "| Lint | ⏭️ SKIP | No lint script |" >> "$OUT_FILE"
  echo "⏭️ Lint skipped (no lint script)"
fi

# Gate: TypeCheck
echo "━━━ Running typecheck..."
if has_npm_script "typecheck"; then
  RAN_ANY=1
  set +e
  TYPES_OUTPUT=$(npm run typecheck 2>&1)
  TYPES_EXIT=$?
  set -e
  
  if [[ $TYPES_EXIT -eq 0 ]]; then
    echo "| Types | ✅ PASS | No type errors |" >> "$OUT_FILE"
    echo "✅ TypeCheck passed"
  else
    TYPE_ERRORS=$(echo "$TYPES_OUTPUT" | grep -c "error TS" || true)
    echo "| Types | ❌ FAIL | $TYPE_ERRORS errors |" >> "$OUT_FILE"
    OVERALL_STATUS="FAIL"
    echo "❌ TypeCheck failed"
  fi
elif [[ -f "tsconfig.json" ]] && command -v tsc &> /dev/null; then
  RAN_ANY=1
  set +e
  TYPES_OUTPUT=$(tsc --noEmit 2>&1)
  TYPES_EXIT=$?
  set -e
  
  if [[ $TYPES_EXIT -eq 0 ]]; then
    echo "| Types | ✅ PASS | No type errors |" >> "$OUT_FILE"
    echo "✅ TypeCheck passed"
  else
    TYPE_ERRORS=$(echo "$TYPES_OUTPUT" | grep -c "error TS" || true)
    echo "| Types | ❌ FAIL | $TYPE_ERRORS errors |" >> "$OUT_FILE"
    OVERALL_STATUS="FAIL"
    echo "❌ TypeCheck failed"
  fi
else
  echo "| Types | ⏭️ SKIP | No typecheck available |" >> "$OUT_FILE"
  echo "⏭️ TypeCheck skipped (no typecheck script or tsc)"
fi

# Gate: Unit Tests
echo "━━━ Running unit tests..."
if has_npm_script "test"; then
  RAN_ANY=1
  set +e
  TEST_OUTPUT=$(npm run test 2>&1)
  TEST_EXIT=$?
  set -e
  
  if [[ $TEST_EXIT -eq 0 ]]; then
    # Try to extract test count
    TESTS_PASSED=$(echo "$TEST_OUTPUT" | grep -oE "[0-9]+ passed" | head -1 || echo "tests")
    echo "| Unit Tests | ✅ PASS | $TESTS_PASSED |" >> "$OUT_FILE"
    echo "✅ Unit tests passed"
  else
    TESTS_FAILED=$(echo "$TEST_OUTPUT" | grep -oE "[0-9]+ failed" | head -1 || echo "some tests")
    echo "| Unit Tests | ❌ FAIL | $TESTS_FAILED |" >> "$OUT_FILE"
    OVERALL_STATUS="FAIL"
    echo "❌ Unit tests failed"
  fi
else
  echo "| Unit Tests | ⏭️ SKIP | No test script |" >> "$OUT_FILE"
  echo "⏭️ Unit tests skipped (no test script)"
fi

# Gate: E2E Tests (optional)
echo "━━━ Running E2E tests..."
if has_npm_script "test:e2e"; then
  RAN_ANY=1
  set +e
  E2E_OUTPUT=$(npm run test:e2e 2>&1)
  E2E_EXIT=$?
  set -e
  
  if [[ $E2E_EXIT -eq 0 ]]; then
    echo "| E2E Tests | ✅ PASS | All passed |" >> "$OUT_FILE"
    echo "✅ E2E tests passed"
  else
    echo "| E2E Tests | ❌ FAIL | See details |" >> "$OUT_FILE"
    OVERALL_STATUS="FAIL"
    echo "❌ E2E tests failed"
  fi
else
  echo "| E2E Tests | ⏭️ SKIP | No test:e2e script |" >> "$OUT_FILE"
  echo "⏭️ E2E tests skipped"
fi

# Gate: Build
echo "━━━ Running build..."
if has_npm_script "build"; then
  RAN_ANY=1
  set +e
  BUILD_OUTPUT=$(npm run build 2>&1)
  BUILD_EXIT=$?
  set -e
  
  if [[ $BUILD_EXIT -eq 0 ]]; then
    # Try to get bundle size
    if [[ -d "dist" ]]; then
      BUNDLE_SIZE=$(du -sh dist 2>/dev/null | cut -f1 || echo "?")
    else
      BUNDLE_SIZE="N/A"
    fi
    echo "| Build | ✅ PASS | Size: $BUNDLE_SIZE |" >> "$OUT_FILE"
    echo "✅ Build passed ($BUNDLE_SIZE)"
  else
    echo "| Build | ❌ FAIL | Build error |" >> "$OUT_FILE"
    OVERALL_STATUS="FAIL"
    echo "❌ Build failed"
  fi
else
  echo "| Build | ⏭️ SKIP | No build script |" >> "$OUT_FILE"
  echo "⏭️ Build skipped"
fi

# Overall status
echo "" >> "$OUT_FILE"
if [[ "$OVERALL_STATUS" == "PASS" ]]; then
  if [[ $RAN_ANY -eq 0 ]]; then
    echo "**Overall: ⚠️ NO AUTOMATED GATES RAN**" >> "$OUT_FILE"
    echo "" >> "$OUT_FILE"
    echo "_Configure package.json scripts (lint/typecheck/test/build) so Gate Pack can do real verification._" >> "$OUT_FILE"
    OVERALL_STATUS="WARN"
  else
    echo "**Overall: ✅ READY FOR REVIEW**" >> "$OUT_FILE"
  fi
else
  echo "**Overall: ❌ NOT READY**" >> "$OUT_FILE"
fi

# Add detailed sections
{
  echo ""
  echo "---"
  echo ""
  echo "## Detailed Results"
  echo ""
  echo "### Lint"
  echo ""
  echo '```'
  printf '%s\n' "${LINT_OUTPUT:-No lint output}" | head -50
  echo '```'
  echo ""
  echo "### Types"
  echo ""
  echo '```'
  printf '%s\n' "${TYPES_OUTPUT:-No typecheck output}" | head -50
  echo '```'
  echo ""
  echo "### Tests"
  echo ""
  echo '```'
  printf '%s\n' "${TEST_OUTPUT:-No test output}" | head -50
  echo '```'
  echo ""
  echo "### E2E Tests"
  echo ""
  echo '```'
  printf '%s\n' "${E2E_OUTPUT:-No E2E output}" | head -50
  echo '```'
  echo ""
  echo "### Build"
  echo ""
  echo '```'
  printf '%s\n' "${BUILD_OUTPUT:-No build output}" | head -50
  echo '```'
} >> "$OUT_FILE"

# Add manual checklist
{
  echo ""
  echo "---"
  echo ""
  echo "## Manual Verification Checklist"
  echo ""
  echo "- [ ] All user flows work correctly"
  echo "- [ ] Error states display properly"
  echo "- [ ] Data persists across reload"
  echo "- [ ] Responsive on mobile"
  echo "- [ ] Keyboard navigation works"
  echo "- [ ] No console errors"
  echo ""
  echo "---"
  echo ""
  echo "## Blockers"
  echo ""
  if [[ "$OVERALL_STATUS" == "FAIL" ]]; then
    echo "- Fix failing gates before proceeding"
  elif [[ "$OVERALL_STATUS" == "WARN" ]]; then
    echo "- No automated gates configured"
  else
    echo "- None"
  fi
} >> "$OUT_FILE"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✅ Verification report written to: $OUT_FILE"
echo ""

if [[ "$OVERALL_STATUS" == "PASS" ]]; then
  echo "╔═══════════════════════════════════════════════════════════════╗"
  echo "║                   ✅ ALL GATES PASSED                         ║"
  echo "╚═══════════════════════════════════════════════════════════════╝"
elif [[ "$OVERALL_STATUS" == "WARN" ]]; then
  echo "╔═══════════════════════════════════════════════════════════════╗"
  echo "║           ⚠️  NO AUTOMATED GATES RAN                          ║"
  echo "║   Configure package.json scripts for real verification       ║"
  echo "╚═══════════════════════════════════════════════════════════════╝"
  exit 1
else
  echo "╔═══════════════════════════════════════════════════════════════╗"
  echo "║                   ❌ GATES FAILED                             ║"
  echo "╚═══════════════════════════════════════════════════════════════╝"
  exit 1
fi
