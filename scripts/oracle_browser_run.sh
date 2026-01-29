#!/usr/bin/env bash
set -euo pipefail

# Oracle Browser Run
# Low-level wrapper for running Oracle in browser mode.
#
# Usage:
#   ./scripts/oracle_browser_run.sh <prompt_file> <output_file> <input_file1> [input_file2...]
#
# Example:
#   ./scripts/oracle_browser_run.sh prompts/prd/security.txt artifacts/06-oracle/prd/20240115-120000_security.md artifacts/01-prd.md
#
# Oracle CLI v0.7.6+ required
# NOTE: GPT-5.2 Pro can take 30-90 minutes for complex reviews. Be patient!

PROMPT_FILE="${1:-}"
OUTPUT_FILE="${2:-}"
shift 2 || true

if [[ -z "$PROMPT_FILE" || -z "$OUTPUT_FILE" || "$#" -lt 1 ]]; then
  echo "Usage: ./scripts/oracle_browser_run.sh <prompt_file> <output_file> <input_files...>"
  exit 1
fi

if [[ ! -f "$PROMPT_FILE" ]]; then
  echo "Error: Prompt file not found: $PROMPT_FILE"
  exit 1
fi

# Build file arguments as array
FILE_ARGS=()
for f in "$@"; do
  if [[ ! -f "$f" ]]; then
    echo "Warning: Input file not found: $f"
  else
    FILE_ARGS+=("--file" "$f")
  fi
done

# Read prompt content
PROMPT_CONTENT=$(cat "$PROMPT_FILE")

# Ensure output directory exists
mkdir -p "$(dirname "$OUTPUT_FILE")"

echo "Running Oracle browser mode..."
echo "  Prompt: $PROMPT_FILE"
echo "  Output: $OUTPUT_FILE"
echo "  Files: $*"
echo ""
echo "⏳ GPT-5.2 Pro can take 30-90 minutes. Be patient!"
echo "⚠️  Keep the Chromium window OPEN until Oracle finishes!"
echo ""

# Try browser automation first
# --browser-manual-login uses persistent Chromium profile (no cookie sync needed)
# --browser-no-cookie-sync explicitly disables Keychain access
# --timeout auto uses 60m for gpt-5.2-pro
# --browser-attachments never forces inline pasting (more reliable)
set +e
npx -y @steipete/oracle \
  --engine browser \
  --browser-manual-login \
  --browser-no-cookie-sync \
  --model gpt-5.2-pro \
  --timeout auto \
  --browser-attachments never \
  --prompt "$PROMPT_CONTENT" \
  "${FILE_ARGS[@]}" \
  --write-output "$OUTPUT_FILE" \
  2>&1
EXIT_CODE=$?
set -e

if [[ $EXIT_CODE -ne 0 ]]; then
  echo ""
  echo "⚠️  Browser automation failed (exit code: $EXIT_CODE)"
  echo ""
  echo "Fallback: Manual paste mode"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Run this command to copy the bundle to clipboard:"
  echo ""
  echo "  npx -y @steipete/oracle --render --copy-markdown \\"
  echo "    --prompt \"\$(cat $PROMPT_FILE)\" \\"
  for f in "$@"; do
    echo "    --file \"$f\" \\"
  done
  echo ""
  echo "Then:"
  echo "1. Paste the bundle into ChatGPT (ensure GPT-5.2 Pro is selected)"
  echo "2. Wait for response (can take 30-90 minutes!)"
  echo "3. Copy the response"
  echo "4. Save to: $OUTPUT_FILE"
  echo ""
  
  # Wait for manual completion (only in interactive mode)
  if [[ -t 0 ]]; then
    echo "Press Enter after saving the output file..."
    read -r
    
    if [[ ! -f "$OUTPUT_FILE" ]]; then
      echo "Error: Output file not found: $OUTPUT_FILE"
      exit 1
    fi
  else
    echo ""
    echo "Non-interactive shell detected; not waiting for manual paste."
    echo "Save output to: $OUTPUT_FILE"
    echo "Then re-run this script or continue your workflow."
    exit 1
  fi
fi

echo "✅ Oracle run complete: $OUTPUT_FILE"
