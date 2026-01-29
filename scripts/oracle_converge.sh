#!/bin/bash
# oracle_converge.sh - FULLY AUTOMATED Oracle convergence loop
#
# This script runs in your terminal and handles EVERYTHING:
# 1. Runs Oracle (30-90 min per iteration)
# 2. Reads issues AND suggestions
# 3. Calls Claude Code to apply fixes (with fresh-eyes review)
# 4. Re-runs Oracle
# 5. Loops until converged (0 blockers/majors) or max rounds
#
# Usage:
#   ./scripts/oracle_converge.sh prd artifacts/01-prd.md artifacts/00-brief.md
#   ./scripts/oracle_converge.sh ux artifacts/02-ux.md artifacts/01-prd.md
#   ./scripts/oracle_converge.sh plan artifacts/03-plan.md artifacts/01-prd.md artifacts/02-ux.md
#
# Convergence rules:
#   - STOP when: blockers + majors == 0
#   - STOP when: rounds >= MAX_ROUNDS (default: 10)
#   - Suggestions are shown but don't block convergence

set -e

MAX_ROUNDS="${MAX_ROUNDS:-10}"
LENS="${LENS:-product}"  # Single lens for iteration speed (can override with LENS env var)

KIND="${1:-}"
PRIMARY_FILE="${2:-}"
shift 2 2>/dev/null || true
CONTEXT_FILES=("$@")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_box() {
  local title="$1"
  local width=75
  echo ""
  printf "╔"; printf '═%.0s' $(seq 1 $width); printf "╗\n"
  printf "║  %-$((width-3))s║\n" "$title"
  printf "╚"; printf '═%.0s' $(seq 1 $width); printf "╝\n"
}

if [ -z "$KIND" ] || [ -z "$PRIMARY_FILE" ]; then
  echo "Usage: $0 <kind> <primary_file> [context_files...]"
  echo ""
  echo "Examples:"
  echo "  $0 prd artifacts/01-prd.md artifacts/00-brief.md"
  echo "  $0 ux artifacts/02-ux.md artifacts/01-prd.md"
  echo "  $0 plan artifacts/03-plan.md artifacts/01-prd.md artifacts/02-ux.md"
  echo ""
  echo "Environment variables:"
  echo "  MAX_ROUNDS=10   Maximum iterations (default: 10)"
  echo "  LENS=product    Which lens to use (default: product)"
  exit 1
fi

# Check dependencies
if ! command -v npx &> /dev/null; then
  echo -e "${RED}ERROR: npx not found. Install Node.js.${NC}"
  exit 1
fi

if ! command -v jq &> /dev/null; then
  echo -e "${YELLOW}WARNING: jq not found. Issue counting will be limited.${NC}"
fi

# Validate files
if [ ! -f "$PRIMARY_FILE" ]; then
  echo -e "${RED}ERROR: Primary file not found: $PRIMARY_FILE${NC}"
  exit 1
fi

for f in "${CONTEXT_FILES[@]}"; do
  if [ ! -f "$f" ]; then
    echo -e "${RED}ERROR: Context file not found: $f${NC}"
    exit 1
  fi
done

# Setup
OUTPUT_DIR="artifacts/06-oracle/$KIND"
mkdir -p "$OUTPUT_DIR"
HISTORY_FILE="$OUTPUT_DIR/convergence-history.json"

# Check for existing state - resume if possible
RESUME_ROUND=1
if [ -f "$HISTORY_FILE" ]; then
  # Check if there's existing progress
  EXISTING_ROUNDS=$(jq -r '.rounds | length' "$HISTORY_FILE" 2>/dev/null || echo "0")
  if [ "$EXISTING_ROUNDS" -gt 0 ]; then
    LAST_ROUND=$(jq -r '.rounds[-1]' "$HISTORY_FILE" 2>/dev/null)
    LAST_BLOCKERS=$(echo "$LAST_ROUND" | jq -r '.blockers // 999')
    LAST_MAJORS=$(echo "$LAST_ROUND" | jq -r '.majors // 999')
    
    # Check if already converged (0 blockers AND 0 majors per CLAUDE.md)
    if [ "$LAST_BLOCKERS" -eq 0 ] && [ "$LAST_MAJORS" -eq 0 ]; then
      echo -e "${GREEN}✅ Already converged! (0 blockers, 0 majors)${NC}"
      echo "   Previous runs found in: $OUTPUT_DIR"
      echo ""
      echo "To force a fresh run, delete $HISTORY_FILE first."
      exit 0
    fi
    
    # Resume from next round
    RESUME_ROUND=$((EXISTING_ROUNDS + 1))
    echo -e "${YELLOW}📍 Resuming from round $RESUME_ROUND (found $EXISTING_ROUNDS previous rounds)${NC}"
    echo "   Last state: $LAST_BLOCKERS blockers, $LAST_MAJORS majors"
    echo ""
  fi
else
  echo '{"rounds": []}' > "$HISTORY_FILE"
fi

print_box "ORACLE CONVERGENCE LOOP v2.1"
echo ""
echo "  Kind:       $KIND"
echo "  Primary:    $PRIMARY_FILE"
echo "  Context:    ${CONTEXT_FILES[*]:-none}"
echo "  Max rounds: $MAX_ROUNDS"
echo "  Lens:       $LENS"
echo ""
echo -e "  ${GREEN}✓ Oracle will AUTO-OPEN Chromium and start immediately${NC}"
echo -e "  ${YELLOW}  Each round: Oracle (30-90 min) + Apply fixes + Fresh-eyes review${NC}"
echo -e "  ${YELLOW}  Total time estimate: 2-12 hours depending on issues${NC}"
echo ""
echo -e "  ${CYAN}💡 Tip: Keep Chromium window open. Go grab a coffee! ☕${NC}"
echo ""

# Convergence history
declare -a HISTORY

ROUND=$RESUME_ROUND
PREV_BLOCKING=999

while [ "$ROUND" -le "$MAX_ROUNDS" ]; do
  print_box "ROUND $ROUND of $MAX_ROUNDS"
  
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  OUTPUT_FILE="$OUTPUT_DIR/${TIMESTAMP}_${LENS}.md"
  ISSUES_FILE="$OUTPUT_DIR/issues-round${ROUND}.json"
  
  # Build file arguments as array (safe for paths with spaces)
  FILE_ARGS_ARRAY=("--file" "$PRIMARY_FILE")
  for f in "${CONTEXT_FILES[@]}"; do
    FILE_ARGS_ARRAY+=("--file" "$f")
  done
  
  # Check if prompt file exists
  PROMPT_FILE="prompts/$KIND/$LENS.txt"
  if [ ! -f "$PROMPT_FILE" ]; then
    echo -e "${RED}ERROR: Prompt file not found: $PROMPT_FILE${NC}"
    exit 1
  fi
  
  echo ""
  echo -e "${BLUE}🔮 Phase 1: Running Oracle ($LENS lens)...${NC}"
  echo "   Started: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "   Output:  $OUTPUT_FILE"
  echo ""
  echo -e "   ${YELLOW}This takes 30-90 minutes. GPT-5.2 Pro is thinking deeply. ☕${NC}"
  echo -e "   ${YELLOW}Keep the Chromium window open until Oracle finishes!${NC}"
  echo ""
  
  # Run Oracle with retry logic (3 attempts before manual fallback)
  # Uses --browser-manual-login for persistent Chromium profile (no cookie sync needed)
  MAX_ATTEMPTS=3
  ATTEMPT=1
  ORACLE_SUCCESS=false
  
  while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    echo -e "${BLUE}   Oracle attempt $ATTEMPT of $MAX_ATTEMPTS...${NC}"
    
    set +e
    npx -y @steipete/oracle \
      --engine browser \
      --browser-manual-login \
      --browser-no-cookie-sync \
      --model gpt-5.2-pro \
      --timeout auto \
      --browser-attachments never \
      --prompt "$(cat "$PROMPT_FILE")" \
      "${FILE_ARGS_ARRAY[@]}" \
      --write-output "$OUTPUT_FILE" 2>&1 | tee "$OUTPUT_DIR/oracle-round${ROUND}-attempt${ATTEMPT}.log"
    ORACLE_EXIT=${PIPESTATUS[0]}
    set -e
    
    if [ $ORACLE_EXIT -eq 0 ] && [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
      ORACLE_SUCCESS=true
      break
    fi
    
    if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
      WAIT_TIME=$((ATTEMPT * 10))  # 10s, 20s, 30s
      echo -e "${YELLOW}   ⚠️ Attempt $ATTEMPT failed. Retrying in ${WAIT_TIME}s... (attempt $((ATTEMPT+1))/$MAX_ATTEMPTS)${NC}"
      sleep $WAIT_TIME
    fi
    
    ATTEMPT=$((ATTEMPT + 1))
  done
  
  if [ "$ORACLE_SUCCESS" = false ]; then
    echo ""
    echo -e "${RED}⚠️  Oracle automation failed after $MAX_ATTEMPTS attempts.${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Make sure Chromium is installed"
    echo "  2. Keep the Chromium window OPEN during Oracle runs"
    echo "  3. Log into ChatGPT in the Chromium window that opens"
    echo ""
    echo "Manual fallback - run in terminal:"
    echo ""
    echo "  npx -y @steipete/oracle --render --copy-markdown \\"
    echo "    --prompt \"\$(cat $PROMPT_FILE)\" \\"
    echo "    ${FILE_ARGS_ARRAY[*]}"
    echo ""
    echo "Then paste into ChatGPT (GPT-5.2 Pro) and save response to:"
    echo "  $OUTPUT_FILE"
    echo ""
    echo "After saving, press ENTER to continue..."
    read -r
    
    # Check if file was created manually
    if [ ! -f "$OUTPUT_FILE" ] || [ ! -s "$OUTPUT_FILE" ]; then
      echo -e "${RED}ERROR: Output file still missing or empty: $OUTPUT_FILE${NC}"
      exit 1
    fi
  fi
  
  echo ""
  echo "   Completed: $(date '+%Y-%m-%d %H:%M:%S')"
  
  # Parse results
  echo ""
  echo -e "${BLUE}📊 Phase 2: Parsing results...${NC}"
  
  # Try to extract JSON from output
  if [ -f "$OUTPUT_FILE" ]; then
    # Extract JSON block from markdown output
    sed -n '/```json/,/```/p' "$OUTPUT_FILE" | sed '1d;$d' > "$ISSUES_FILE" 2>/dev/null || true
  fi
  
  # Count issues
  BLOCKERS=0
  MAJORS=0
  MINORS=0
  NITS=0
  SUGGESTIONS=0
  CONFIDENCE=0
  READY="unknown"
  
  if [ -f "$ISSUES_FILE" ] && [ -s "$ISSUES_FILE" ] && command -v jq &> /dev/null; then
    BLOCKERS=$(jq '[.issues[]? | select(.severity == "blocker")] | length' "$ISSUES_FILE" 2>/dev/null || echo "0")
    MAJORS=$(jq '[.issues[]? | select(.severity == "major")] | length' "$ISSUES_FILE" 2>/dev/null || echo "0")
    MINORS=$(jq '[.issues[]? | select(.severity == "minor")] | length' "$ISSUES_FILE" 2>/dev/null || echo "0")
    NITS=$(jq '[.issues[]? | select(.severity == "nit")] | length' "$ISSUES_FILE" 2>/dev/null || echo "0")
    SUGGESTIONS=$(jq '.suggestions | length' "$ISSUES_FILE" 2>/dev/null || echo "0")
    CONFIDENCE=$(jq '.overallAssessment.confidenceScore // 0' "$ISSUES_FILE" 2>/dev/null || echo "0")
    READY=$(jq -r '.overallAssessment.readyForImplementation // "unknown"' "$ISSUES_FILE" 2>/dev/null || echo "unknown")
  fi
  
  TOTAL=$((BLOCKERS + MAJORS + MINORS + NITS))
  BLOCKING=$((BLOCKERS + MAJORS))
  
  # Record history
  HISTORY+=("Round $ROUND: $BLOCKERS blocker, $MAJORS major, $MINORS minor, $NITS nit | $SUGGESTIONS suggestions | confidence: $CONFIDENCE")
  
  # Update history file
  if command -v jq &> /dev/null; then
    jq ".rounds += [{\"round\": $ROUND, \"blockers\": $BLOCKERS, \"majors\": $MAJORS, \"minors\": $MINORS, \"nits\": $NITS, \"suggestions\": $SUGGESTIONS, \"confidence\": $CONFIDENCE}]" "$HISTORY_FILE" > "$HISTORY_FILE.tmp" && mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"
  fi
  
  echo ""
  echo "┌─────────────────────────────────────────────────────────────┐"
  printf "│  %-57s │\n" "Round $ROUND Results"
  echo "├─────────────────────────────────────────────────────────────┤"
  printf "│  ${RED}Blockers:${NC}    %-46s │\n" "$BLOCKERS"
  printf "│  ${YELLOW}Majors:${NC}      %-46s │\n" "$MAJORS"
  printf "│  Minors:     %-46s │\n" "$MINORS"
  printf "│  Nits:       %-46s │\n" "$NITS"
  echo "├─────────────────────────────────────────────────────────────┤"
  printf "│  ${CYAN}Suggestions:${NC} %-46s │\n" "$SUGGESTIONS"
  printf "│  Confidence: %-46s │\n" "$CONFIDENCE/10"
  printf "│  Ready:      %-46s │\n" "$READY"
  echo "└─────────────────────────────────────────────────────────────┘"
  
  # Check convergence
  if [ "$BLOCKING" -eq 0 ]; then
    print_box "✅ CONVERGED after $ROUND round(s)!"
    echo ""
    echo -e "${GREEN}No blockers or major issues remaining.${NC}"
    if [ "$MINORS" -gt 0 ] || [ "$NITS" -gt 0 ]; then
      echo "Deferred: $MINORS minor(s), $NITS nit(s)"
    fi
    if [ "$SUGGESTIONS" -gt 0 ]; then
      echo -e "${CYAN}Suggestions available: $SUGGESTIONS (review in $ISSUES_FILE)${NC}"
    fi
    echo ""
    echo "Convergence History:"
    for h in "${HISTORY[@]}"; do
      echo "  $h"
    done
    echo ""
    echo -e "${GREEN}Overall confidence: $CONFIDENCE/10${NC}"
    echo ""
    echo "Next step:"
    case "$KIND" in
      prd) echo -e "  ${GREEN}/ux${NC} - Generate UX specification" ;;
      ux)  echo -e "  ${GREEN}/plan${NC} - Generate implementation plan" ;;
      plan) 
        echo -e "  ${GREEN}Auto-compiling task graph...${NC}"
        echo ""
        # Auto-run artifact-tasks for plan convergence
        if command -v node &> /dev/null && [ -f "scripts/compile_task_graph.js" ]; then
          echo "Compiling task graph..."
          node scripts/compile_task_graph.js \
            --plan artifacts/03-plan.md \
            --issues "$ISSUES_FILE" \
            --out artifacts/04-task-graph.json 2>/dev/null || true
          
          if [ -f "artifacts/04-task-graph.json" ]; then
            TASK_COUNT=$(jq '.tasks | length' artifacts/04-task-graph.json 2>/dev/null || echo "?")
            echo -e "  ${GREEN}✅ Task graph compiled: $TASK_COUNT tasks${NC}"
          fi
        fi
        echo ""
        echo "Next steps:"
        echo -e "  1. ${GREEN}bash artifacts/04-beads-setup.sh${NC}  # Create beads from tasks"
        echo -e "  2. ${GREEN}/review beads${NC}                     # Run 6-9 times!"
        echo -e "  3. ${GREEN}./scripts/ralph.sh --beads --fresh-eyes 100${NC}"
        ;;
      code) echo -e "  ${GREEN}/gates${NC} - Run quality gates" ;;
    esac
    echo ""
    
    # Copy final issues
    [ -f "$ISSUES_FILE" ] && cp "$ISSUES_FILE" "$OUTPUT_DIR/issues.json"
    exit 0
  fi
  
  # Check if stuck (same blocking count 3 times)
  if [ "$BLOCKING" -eq "$PREV_BLOCKING" ] && [ "$ROUND" -gt 2 ]; then
    echo ""
    echo -e "${YELLOW}⚠️  Same number of blocking issues for 2+ rounds.${NC}"
    echo "   This may indicate false positives or unresolvable issues."
    echo ""
  fi
  PREV_BLOCKING=$BLOCKING
  
  if [ "$ROUND" -eq "$MAX_ROUNDS" ]; then
    print_box "⚠️  MAX ROUNDS ($MAX_ROUNDS) reached"
    echo ""
    echo -e "${YELLOW}Remaining: $BLOCKERS blocker(s), $MAJORS major(s)${NC}"
    echo ""
    echo "Convergence History:"
    for h in "${HISTORY[@]}"; do
      echo "  $h"
    done
    echo ""
    echo "Options:"
    echo "  1. Review remaining issues manually (may be false positives)"
    echo "  2. Increase rounds: MAX_ROUNDS=15 $0 $KIND $PRIMARY_FILE ${CONTEXT_FILES[*]}"
    echo "  3. Proceed anyway if issues are edge cases"
    echo ""
    
    [ -f "$ISSUES_FILE" ] && cp "$ISSUES_FILE" "$OUTPUT_DIR/issues.json"
    exit 1
  fi
  
  # Apply fixes
  echo ""
  echo -e "${BLUE}📝 Phase 3: Apply fixes via Claude Code...${NC}"
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "  APPLY FEEDBACK"
  echo "════════════════════════════════════════════════════════════════"
  echo ""
  echo "In Claude Code, run:"
  echo ""
  echo -e "  ${GREEN}/oracle $KIND${NC}"
  echo ""
  echo "This will:"
  echo "  1. Read the Oracle output from $OUTPUT_FILE"
  echo "  2. Evaluate each issue critically"
  echo "  3. Apply fixes to $PRIMARY_FILE"
  echo "  4. Run fresh-eyes review"
  echo "  5. Report what was applied/dismissed"
  echo ""
  echo -e "${YELLOW}Press ENTER when fixes are applied to continue to round $((ROUND + 1))...${NC}"
  read -r
  
  ROUND=$((ROUND + 1))
done

echo ""
echo -e "${RED}ERROR: Should not reach here${NC}"
exit 1
