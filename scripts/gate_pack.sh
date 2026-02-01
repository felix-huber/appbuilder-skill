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

# Get the command for a given task type (lint, test, build, typecheck)
# Multi-stack support: Makefile > npm > Python > Rust > Go
get_cmd() {
  local cmd_type="$1"
  # Makefile is the universal override
  if [[ -f "Makefile" ]] && grep -q "^${cmd_type}:" Makefile 2>/dev/null; then
    echo "make $cmd_type"; return 0
  fi
  # Node.js
  if [[ -f "package.json" ]]; then
    if has_npm_script "$cmd_type"; then
      echo "npm run $cmd_type"; return 0
    fi
    # Fallback for typecheck variations
    if [[ "$cmd_type" == "typecheck" ]]; then
      has_npm_script "type-check" && echo "npm run type-check" && return 0
      has_npm_script "types" && echo "npm run types" && return 0
      [[ -f "tsconfig.json" ]] && command -v tsc &>/dev/null && echo "tsc --noEmit" && return 0
    fi
  fi
  # Python
  if [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]] || [[ -f "requirements.txt" ]]; then
    case "$cmd_type" in
      lint) echo "ruff check ." ;;
      test) echo "pytest -v" ;;
      typecheck) echo "mypy ." ;;
      build) echo "pip install -e ." ;;
    esac
    return 0
  fi
  # Rust
  if [[ -f "Cargo.toml" ]]; then
    case "$cmd_type" in
      lint) echo "cargo clippy -- -D warnings" ;;
      test) echo "cargo test" ;;
      typecheck) echo "cargo check" ;;
      build) echo "cargo build --release" ;;
    esac
    return 0
  fi
  # Go
  if [[ -f "go.mod" ]]; then
    case "$cmd_type" in
      lint) echo "go vet ./..." ;;
      test) echo "go test -v ./..." ;;
      typecheck) echo "go build ./..." ;;
      build) echo "go build -o bin/ ./..." ;;
    esac
    return 0
  fi
  return 1
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
LINT_CMD=$(get_cmd "lint" 2>/dev/null || true)
if [[ -n "$LINT_CMD" ]]; then
  RAN_ANY=1
  set +e
  LINT_OUTPUT=$(eval "$LINT_CMD" 2>&1)
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

# Gate: AI-Specific Lint (AppBuilder v2)
# These rules catch common AI-generated code mistakes
echo "━━━ Running AI-specific lint checks..."
AI_LINT_ERRORS=0
AI_LINT_OUTPUT=""

# Rule 1: Hardcoded secrets (CRITICAL - all languages)
SECRET_MATCHES=$(grep -rn --include="*.py" --include="*.ts" --include="*.js" --include="*.go" --include="*.rs" \
  -E "(api[_-]?key|secret|password|token)\s*[=:]\s*['\"][A-Za-z0-9_\-]{20,}" . 2>/dev/null | \
  grep -v "node_modules" | grep -v ".git" | head -10 || true)
if [[ -n "$SECRET_MATCHES" ]]; then
  AI_LINT_OUTPUT+="❌ CRITICAL: Potential hardcoded secrets:\n$SECRET_MATCHES\n\n"
  AI_LINT_ERRORS=$((AI_LINT_ERRORS + 1))
fi

# Rule 2: SQL injection (string interpolation in SQL) - CRITICAL, NO BYPASS
SQL_INJECTION=$(grep -rn --include="*.py" --include="*.ts" --include="*.js" \
  -E "(SELECT|INSERT|UPDATE|DELETE|FROM|WHERE).*(\\\$\{|f['\"])" . 2>/dev/null | \
  grep -v "node_modules" | grep -v ".git" | head -10 || true)
if [[ -n "$SQL_INJECTION" ]]; then
  AI_LINT_OUTPUT+="❌ CRITICAL: Potential SQL injection (use parameterized queries):\n$SQL_INJECTION\n\n"
  AI_LINT_ERRORS=$((AI_LINT_ERRORS + 1))
fi

# Rule 3: Python mutable default arguments
MUTABLE_DEFAULT=$(grep -rn --include="*.py" \
  -E "def [a-zA-Z_]+\([^)]*=\s*(\[\]|\{\}|set\(\))" . 2>/dev/null | \
  grep -v "node_modules" | grep -v ".git" | grep -vi "# SAFETY" | head -10 || true)
if [[ -n "$MUTABLE_DEFAULT" ]]; then
  AI_LINT_OUTPUT+="❌ ERROR: Python mutable default argument (use None instead):\n$MUTABLE_DEFAULT\n\n"
  AI_LINT_ERRORS=$((AI_LINT_ERRORS + 1))
fi

# Rule 4: Shell injection (subprocess with shell=True) - CRITICAL, NO BYPASS
SHELL_INJECTION=$(grep -rn --include="*.py" \
  -E "subprocess\.(run|call|Popen)\([^)]*shell\s*=\s*True" . 2>/dev/null | \
  grep -v "node_modules" | grep -v ".git" | head -10 || true)
if [[ -n "$SHELL_INJECTION" ]]; then
  AI_LINT_OUTPUT+="❌ CRITICAL: subprocess with shell=True (use shell=False with list args):\n$SHELL_INJECTION\n\n"
  AI_LINT_ERRORS=$((AI_LINT_ERRORS + 1))
fi

# Rule 5: TypeScript 'any' type overuse
ANY_TYPE=$(grep -rn --include="*.ts" --include="*.tsx" \
  -E ":\s*any\b" . 2>/dev/null | \
  grep -v "node_modules" | grep -v ".git" | grep -v "\.d\.ts" | head -20 || true)
ANY_COUNT=$(echo "$ANY_TYPE" | grep -c "." 2>/dev/null || echo "0")
if [[ "$ANY_COUNT" -gt 5 ]]; then
  AI_LINT_OUTPUT+="⚠️ WARNING: Excessive 'any' type usage ($ANY_COUNT instances):\n$(echo "$ANY_TYPE" | head -5)\n...\n\n"
fi

# Rule 6: Unhandled promise rejection
UNHANDLED_PROMISE=$(grep -rn --include="*.ts" --include="*.js" \
  -E "\.then\s*\([^)]+\)\s*$" . 2>/dev/null | \
  grep -v "node_modules" | grep -v ".git" | grep -v "\.catch" | head -10 || true)
if [[ -n "$UNHANDLED_PROMISE" ]]; then
  AI_LINT_OUTPUT+="⚠️ WARNING: Promise without .catch() handler:\n$UNHANDLED_PROMISE\n\n"
fi

# Rule 7: Go unchecked errors (basic pattern)
GO_UNCHECKED=$(grep -rn --include="*.go" \
  -E "^\s*[a-zA-Z_]+\s*\(" . 2>/dev/null | \
  grep -v "node_modules" | grep -v ".git" | grep -v "if err" | \
  grep -E "(Open|Read|Write|Close|Exec|Query)\(" | head -10 || true)
# This is a heuristic - Go's tooling handles this better

# Rule 8: Rust unwrap without context
RUST_UNWRAP=$(grep -rn --include="*.rs" \
  -E "\.unwrap\(\)" . 2>/dev/null | \
  grep -v "target/" | grep -v "// SAFETY" | head -10 || true)
UNWRAP_COUNT=$(echo "$RUST_UNWRAP" | grep -c "." 2>/dev/null || echo "0")
if [[ "$UNWRAP_COUNT" -gt 3 ]]; then
  AI_LINT_OUTPUT+="⚠️ WARNING: Rust .unwrap() without safety comment ($UNWRAP_COUNT instances):\n$(echo "$RUST_UNWRAP" | head -3)\n...\n\n"
fi

# Report AI lint results
if [[ $AI_LINT_ERRORS -gt 0 ]]; then
  echo "| AI Lint | ❌ FAIL | $AI_LINT_ERRORS critical issues |" >> "$OUT_FILE"
  OVERALL_STATUS="FAIL"
  echo "❌ AI-specific lint failed ($AI_LINT_ERRORS critical issues)"
  echo ""
  echo -e "$AI_LINT_OUTPUT"
elif [[ -n "$AI_LINT_OUTPUT" ]]; then
  echo "| AI Lint | ⚠️ WARN | Warnings found |" >> "$OUT_FILE"
  echo "⚠️ AI-specific lint passed with warnings"
else
  echo "| AI Lint | ✅ PASS | No AI-specific issues |" >> "$OUT_FILE"
  echo "✅ AI-specific lint passed"
fi

# Gate: TypeCheck
echo "━━━ Running typecheck..."
TYPECHECK_CMD=$(get_cmd "typecheck" 2>/dev/null || true)
if [[ -n "$TYPECHECK_CMD" ]]; then
  RAN_ANY=1
  set +e
  TYPES_OUTPUT=$(eval "$TYPECHECK_CMD" 2>&1)
  TYPES_EXIT=$?
  set -e

  if [[ $TYPES_EXIT -eq 0 ]]; then
    echo "| Types | ✅ PASS | No type errors |" >> "$OUT_FILE"
    echo "✅ TypeCheck passed"
  else
    TYPE_ERRORS=$(echo "$TYPES_OUTPUT" | grep -ciE "error" || true)
    echo "| Types | ❌ FAIL | $TYPE_ERRORS errors |" >> "$OUT_FILE"
    OVERALL_STATUS="FAIL"
    echo "❌ TypeCheck failed"
  fi
else
  echo "| Types | ⏭️ SKIP | No typecheck available |" >> "$OUT_FILE"
  echo "⏭️ TypeCheck skipped"
fi

# Gate: Unit Tests
echo "━━━ Running unit tests..."
TEST_CMD=$(get_cmd "test" 2>/dev/null || true)
if [[ -n "$TEST_CMD" ]]; then
  RAN_ANY=1
  set +e
  TEST_OUTPUT=$(eval "$TEST_CMD" 2>&1)
  TEST_EXIT=$?
  set -e

  if [[ $TEST_EXIT -eq 0 ]]; then
    # Try to extract test count (works for most frameworks)
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
  echo "| Unit Tests | ⏭️ SKIP | No test command |" >> "$OUT_FILE"
  echo "⏭️ Unit tests skipped (no test command)"
fi

# Gate: E2E Tests (optional)
# Check multiple sources: npm script, Makefile, or standalone script
echo "━━━ Running E2E tests..."
E2E_CMD=""
if has_npm_script "test:e2e"; then
  E2E_CMD="npm run test:e2e"
elif [[ -f "Makefile" ]] && grep -q "^test-e2e:" Makefile 2>/dev/null; then
  E2E_CMD="make test-e2e"
elif [[ -f "Makefile" ]] && grep -q "^e2e:" Makefile 2>/dev/null; then
  E2E_CMD="make e2e"
elif [[ -x "scripts/run_e2e_happy_paths.sh" ]]; then
  E2E_CMD="./scripts/run_e2e_happy_paths.sh"
fi

if [[ -n "$E2E_CMD" ]]; then
  RAN_ANY=1
  set +e
  E2E_OUTPUT=$(eval "$E2E_CMD" 2>&1)
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
  echo "| E2E Tests | ⏭️ SKIP | No E2E test command found |" >> "$OUT_FILE"
  echo "⏭️ E2E tests skipped"
fi

# Gate: Build
echo "━━━ Running build..."
BUILD_CMD=$(get_cmd "build" 2>/dev/null || true)
if [[ -n "$BUILD_CMD" ]]; then
  RAN_ANY=1
  set +e
  BUILD_OUTPUT=$(eval "$BUILD_CMD" 2>&1)
  BUILD_EXIT=$?
  set -e

  if [[ $BUILD_EXIT -eq 0 ]]; then
    # Try to get bundle size (check common output dirs)
    BUNDLE_SIZE="N/A"
    for dir in dist build target/release out; do
      if [[ -d "$dir" ]]; then
        BUNDLE_SIZE=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "?")
        break
      fi
    done
    echo "| Build | ✅ PASS | Size: $BUNDLE_SIZE |" >> "$OUT_FILE"
    echo "✅ Build passed ($BUNDLE_SIZE)"
  else
    echo "| Build | ❌ FAIL | Build error |" >> "$OUT_FILE"
    OVERALL_STATUS="FAIL"
    echo "❌ Build failed"
  fi
else
  echo "| Build | ⏭️ SKIP | No build command |" >> "$OUT_FILE"
  echo "⏭️ Build skipped"
fi

# Overall status
echo "" >> "$OUT_FILE"
if [[ "$OVERALL_STATUS" == "PASS" ]]; then
  if [[ $RAN_ANY -eq 0 ]]; then
    echo "**Overall: ⚠️ NO AUTOMATED GATES RAN**" >> "$OUT_FILE"
    echo "" >> "$OUT_FILE"
    echo "_Configure build scripts (Makefile, package.json, pyproject.toml, Cargo.toml, or go.mod) so Gate Pack can do real verification._" >> "$OUT_FILE"
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
  echo "║   Configure build system (Makefile, package.json, etc.)      ║"
  echo "╚═══════════════════════════════════════════════════════════════╝"
  exit 1
else
  echo "╔═══════════════════════════════════════════════════════════════╗"
  echo "║                   ❌ GATES FAILED                             ║"
  echo "╚═══════════════════════════════════════════════════════════════╝"
  exit 1
fi
