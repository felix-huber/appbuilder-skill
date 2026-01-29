#!/bin/bash
# run_e2e_happy_paths.sh - Run E2E tests for all happy path user journeys
#
# This script uses agent-browser to test critical user journeys.
# Happy paths (marked with ⭐ in artifacts/02-ux.md) are tested on every build.
#
# Prerequisites:
#   npm install -g agent-browser
#   agent-browser install
#
# Usage:
#   ./scripts/run_e2e_happy_paths.sh
#   ./scripts/run_e2e_happy_paths.sh --headed  # Show browser

set -e

HEADED=""
if [[ "$1" == "--headed" ]]; then
  HEADED="--headed"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Create output directory
mkdir -p artifacts/e2e

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  E2E HAPPY PATH TESTS"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Check for agent-browser
if ! command -v agent-browser &> /dev/null; then
  echo -e "${RED}ERROR: agent-browser not found${NC}"
  echo ""
  echo "Install with:"
  echo "  npm install -g agent-browser"
  echo "  agent-browser install"
  exit 1
fi

# Start dev server
echo -e "${BLUE}Starting dev server...${NC}"
npm run preview &
SERVER_PID=$!

# Wait for server
sleep 5

# Trap to cleanup
cleanup() {
  echo ""
  echo -e "${BLUE}Cleaning up...${NC}"
  kill $SERVER_PID 2>/dev/null || true
  agent-browser close 2>/dev/null || true
}
trap cleanup EXIT

# Get server URL
BASE_URL="${BASE_URL:-http://localhost:4173}"

echo -e "${BLUE}Server running at $BASE_URL${NC}"
echo ""

# Track results
PASSED=0
FAILED=0
TESTS=()

run_test() {
  local name="$1"
  local description="$2"
  shift 2
  local commands=("$@")
  
  echo -e "${BLUE}Testing: $name${NC}"
  echo "  $description"
  
  local success=true
  for cmd in "${commands[@]}"; do
    echo "  > $cmd"
    if ! eval "$cmd" 2>/dev/null; then
      success=false
      break
    fi
  done
  
  if $success; then
    echo -e "  ${GREEN}✅ PASSED${NC}"
    PASSED=$((PASSED + 1))
    TESTS+=("✅ $name")
  else
    echo -e "  ${RED}❌ FAILED${NC}"
    FAILED=$((FAILED + 1))
    TESTS+=("❌ $name")
  fi
  echo ""
}

# ═══════════════════════════════════════════════════════════════════
# ADD YOUR HAPPY PATH TESTS BELOW
# Copy from artifacts/02-ux.md User Journeys section
# ═══════════════════════════════════════════════════════════════════

# Example test (replace with your actual tests)
run_test "UJ-001: App Loads" "Verify app loads successfully" \
  "agent-browser open $BASE_URL $HEADED" \
  "agent-browser wait --load networkidle" \
  "agent-browser screenshot artifacts/e2e/uj-001-load.png"

# Uncomment and customize these based on your UX spec:
#
# run_test "UJ-002: Create Database" "User can create a new database" \
#   "agent-browser open $BASE_URL $HEADED" \
#   "agent-browser snapshot -i" \
#   "agent-browser click @e3" \
#   "agent-browser wait --text 'Tables'" \
#   "agent-browser screenshot artifacts/e2e/uj-002-create.png"
#
# run_test "UJ-003: Run Query" "User can execute SQL query" \
#   "agent-browser fill @e10 'SELECT * FROM users'" \
#   "agent-browser click @e11" \
#   "agent-browser wait --text 'rows'" \
#   "agent-browser screenshot artifacts/e2e/uj-003-query.png"

# ═══════════════════════════════════════════════════════════════════
# RESULTS
# ═══════════════════════════════════════════════════════════════════

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  E2E TEST RESULTS"
echo "════════════════════════════════════════════════════════════════"
echo ""

for test in "${TESTS[@]}"; do
  echo "  $test"
done

echo ""
echo "────────────────────────────────────────────────────────────────"
echo -e "  Passed: ${GREEN}$PASSED${NC}"
echo -e "  Failed: ${RED}$FAILED${NC}"
echo "────────────────────────────────────────────────────────────────"

if [ $FAILED -gt 0 ]; then
  echo ""
  echo -e "${RED}❌ E2E TESTS FAILED${NC}"
  echo ""
  echo "Screenshots saved to: artifacts/e2e/"
  exit 1
else
  echo ""
  echo -e "${GREEN}✅ ALL E2E TESTS PASSED${NC}"
  exit 0
fi
