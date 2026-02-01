#!/bin/bash
# run_e2e_happy_paths.sh - Run E2E tests for all happy path user journeys
#
# This script uses agent-browser to test critical user journeys.
# Happy paths (marked with ⭐ in artifacts/02-ux.md) are tested on every build.
#
# Supports multiple stacks: Node.js, Python/Flask, Rust, Go
#
# Prerequisites:
#   npm install -g agent-browser
#   agent-browser install
#
# Usage:
#   ./scripts/run_e2e_happy_paths.sh
#   ./scripts/run_e2e_happy_paths.sh --headed  # Show browser

set -euo pipefail

HEADED=""
if [[ "${1:-}" == "--headed" ]]; then
  HEADED="--headed"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
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

# Detect stack and get dev server command + default port
get_dev_server() {
  # Makefile override
  if [[ -f "Makefile" ]] && grep -q "^dev:" Makefile 2>/dev/null; then
    echo "make dev"
    return 0
  fi
  # Node.js
  if [[ -f "package.json" ]]; then
    if grep -q '"preview"' package.json 2>/dev/null; then
      echo "npm run preview"
    elif grep -q '"dev"' package.json 2>/dev/null; then
      echo "npm run dev"
    elif grep -q '"start"' package.json 2>/dev/null; then
      echo "npm start"
    else
      echo "npm run dev"
    fi
    return 0
  fi
  # Python
  if [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]] || [[ -f "requirements.txt" ]]; then
    if [[ -f "app.py" ]] || [[ -f "application.py" ]]; then
      echo "flask run --debug"
    elif [[ -f "main.py" ]] && command -v uvicorn &>/dev/null; then
      echo "uvicorn main:app --reload"
    elif [[ -f "main.py" ]]; then
      echo "python main.py"
    else
      echo "flask run --debug"
    fi
    return 0
  fi
  # Rust (web frameworks like Actix, Axum)
  if [[ -f "Cargo.toml" ]]; then
    echo "cargo run"
    return 0
  fi
  # Go
  if [[ -f "go.mod" ]]; then
    echo "go run ."
    return 0
  fi
  # Ruby
  if [[ -f "Gemfile" ]]; then
    if [[ -f "config/application.rb" ]]; then
      echo "bundle exec rails server"
    else
      echo "bundle exec rackup"
    fi
    return 0
  fi
  # No recognized stack - fail loudly
  echo ""
  return 1
}

# Find a free port in the ephemeral range
get_free_port() {
  # Try Python first (most reliable)
  if command -v python3 &>/dev/null; then
    python3 -c "import socket; s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()" 2>/dev/null && return
  fi
  if command -v python &>/dev/null; then
    python -c "import socket; s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()" 2>/dev/null && return
  fi
  # Fallback: pick random port in 10000-60000 range and hope it's free
  echo $((10000 + RANDOM % 50000))
}

# Get port override flag for dev server command
get_port_flag() {
  local port="$1"
  # Node.js (Vite, Next, etc.) - needs -- before flags
  if [[ -f "package.json" ]]; then
    echo "-- --port $port"
    return
  fi
  # Python Flask/uvicorn
  if [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]] || [[ -f "requirements.txt" ]]; then
    echo "--port $port"
    return
  fi
  # Rust/Go typically use env vars, handled separately
  echo ""
}

# Start dev server on random port (allows parallel runs)
DEV_CMD=$(get_dev_server) || true
if [[ -z "$DEV_CMD" ]]; then
  echo -e "${RED}ERROR: No recognized project stack found${NC}"
  echo "Supported: package.json (Node), pyproject.toml/requirements.txt (Python),"
  echo "           Cargo.toml (Rust), go.mod (Go), Gemfile (Ruby), or Makefile with 'dev' target"
  exit 1
fi
PORT=${PORT:-$(get_free_port)}
BASE_URL="http://localhost:$PORT"
PORT_FLAG=$(get_port_flag "$PORT")

# Build full command with port
if [[ -n "$PORT_FLAG" ]]; then
  FULL_CMD="$DEV_CMD $PORT_FLAG"
else
  # Use PORT env var for frameworks that support it (Go, Rust, etc.)
  FULL_CMD="PORT=$PORT $DEV_CMD"
fi

echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Server: $BASE_URL${NC}"
echo -e "${BLUE}  Command: $FULL_CMD${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""
eval "$FULL_CMD" &
SERVER_PID=$!
echo -e "${BLUE}Started server PID $SERVER_PID → $BASE_URL${NC}"

# Wait for server to be ready with health check
echo -e "${BLUE}Waiting for $BASE_URL ...${NC}"
MAX_WAIT=30
WAITED=0
while ! curl -s "$BASE_URL" >/dev/null 2>&1; do
  sleep 1
  WAITED=$((WAITED + 1))
  # Check if server process died
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo -e "${RED}ERROR: Server process died (PID $SERVER_PID)${NC}"
    echo -e "${RED}Check command: $FULL_CMD${NC}"
    exit 1
  fi
  if [[ $WAITED -ge $MAX_WAIT ]]; then
    echo -e "${RED}ERROR: Server did not respond at $BASE_URL within ${MAX_WAIT}s${NC}"
    echo -e "${RED}PID: $SERVER_PID | To kill: kill $SERVER_PID${NC}"
    exit 1
  fi
done
echo -e "${GREEN}✓ Server ready at $BASE_URL (${WAITED}s, PID $SERVER_PID)${NC}"
echo ""

# Trap to cleanup
cleanup() {
  echo ""
  echo -e "${BLUE}Stopping server at $BASE_URL (PID $SERVER_PID)...${NC}"
  kill $SERVER_PID 2>/dev/null || true
  agent-browser close 2>/dev/null || true
}
trap cleanup EXIT

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
    if ! eval "$cmd"; then
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
echo -e "  Server: $BASE_URL (PID $SERVER_PID)"
echo "────────────────────────────────────────────────────────────────"

if [ $FAILED -gt 0 ]; then
  echo ""
  echo -e "${RED}❌ E2E TESTS FAILED${NC}"
  echo ""
  echo "Screenshots: artifacts/e2e/"
  echo "Server was: $BASE_URL (PID $SERVER_PID)"
  echo "Kill if stuck: kill $SERVER_PID"
  exit 1
else
  echo ""
  echo -e "${GREEN}✅ ALL E2E TESTS PASSED${NC}"
  exit 0
fi
