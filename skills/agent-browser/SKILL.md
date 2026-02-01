---
name: agent-browser
description: Browser automation for E2E testing. Use when testing user journeys, verifying UI behavior, or running end-to-end tests.
---

# agent-browser — E2E Testing Skill

Use `agent-browser` for browser automation and E2E testing.

## Installation

```bash
npm install -g agent-browser
agent-browser install  # Downloads Chromium
```

## Core Workflow

Note: Examples use `localhost:3000` as a placeholder. In practice, use the actual server URL (e.g., from `$BASE_URL` in scripts).

```bash
# 1. Open page (use your actual server URL)
agent-browser open http://localhost:3000

# 2. Get interactive elements with refs (@e1, @e2, etc.)
agent-browser snapshot -i

# 3. Interact using refs
agent-browser click @e2
agent-browser fill @e5 "test@example.com"

# 4. Re-snapshot after page changes
agent-browser snapshot -i

# 5. Verify result
agent-browser wait --text "Success"

# 6. Screenshot for evidence
agent-browser screenshot result.png

# 7. Close
agent-browser close
```

## Common Commands

### Navigation
```bash
agent-browser open <url>      # Navigate to URL
agent-browser back            # Go back
agent-browser forward         # Go forward
agent-browser reload          # Reload page
agent-browser close           # Close browser
```

### Element Discovery
```bash
agent-browser snapshot        # Full accessibility tree
agent-browser snapshot -i     # Interactive elements only (RECOMMENDED)
agent-browser snapshot -c     # Compact output
```

### Interaction
```bash
agent-browser click @e1       # Click element
agent-browser dblclick @e1    # Double-click
agent-browser fill @e2 "text" # Clear and type
agent-browser type @e2 "text" # Type without clearing
agent-browser check @e3       # Check checkbox
agent-browser uncheck @e3     # Uncheck
agent-browser select @e4 "option"  # Select dropdown
agent-browser hover @e5       # Hover
```

### Keyboard
```bash
agent-browser press Enter     # Press key
agent-browser press Tab
agent-browser press Control+a # Combination
```

### Waiting
```bash
agent-browser wait @e1              # Wait for element
agent-browser wait 2000             # Wait milliseconds
agent-browser wait --text "Success" # Wait for text
agent-browser wait --url "**/dashboard"  # Wait for URL
agent-browser wait --load networkidle    # Wait for network idle
```

### Screenshots
```bash
agent-browser screenshot page.png      # Current viewport
agent-browser screenshot --full full.png  # Full page
```

### File Upload
```bash
agent-browser upload @e10 "path/to/file.db"
```

### JavaScript Evaluation
```bash
agent-browser eval "document.title"
agent-browser eval "window.localStorage.clear()"
```

## Testing User Journeys

For each user journey in `artifacts/02-ux.md`, create E2E commands:

### Example: UJ-001 Create Database
```bash
# Start fresh
agent-browser open http://localhost:3000

# Get elements
agent-browser snapshot -i
# Output: @e1 "Create Database" button, @e2 "Import" button

# Execute journey
agent-browser click @e1
agent-browser wait --text "Tables"
agent-browser screenshot artifacts/e2e/uj-001.png

# Verify success
agent-browser snapshot -i
# Should show table list UI
```

### Example: UJ-002 Run SQL Query
```bash
# Assumes database is loaded
agent-browser fill @e10 "SELECT * FROM users LIMIT 5"
agent-browser click @e11  # Run button
agent-browser wait --text "5 rows"
agent-browser screenshot artifacts/e2e/uj-002.png
```

## Integration with Ralph

For E2E tests, use the provided script which handles multi-stack detection and random ports:

```bash
# Run E2E happy path tests (auto-detects stack, uses random port)
./scripts/run_e2e_happy_paths.sh

# Show browser during tests
./scripts/run_e2e_happy_paths.sh --headed

# Override port if needed
PORT=8080 ./scripts/run_e2e_happy_paths.sh
```

Add E2E verification to task (manual approach):

```json
{
  "verification": [
    "./scripts/run_e2e_happy_paths.sh"
  ]
}
```

## Debugging

```bash
# Show browser window (not headless)
agent-browser --headed open http://localhost:3000

# Get more details
agent-browser snapshot  # Full tree, not just interactive

# Check what's on page
agent-browser eval "document.body.innerText"
```

## Common Patterns

### Login Flow
```bash
agent-browser open http://localhost:3000/login
agent-browser snapshot -i
agent-browser fill @e2 "user@example.com"
agent-browser fill @e3 "password123"
agent-browser click @e4  # Submit
agent-browser wait --url "**/dashboard"
```

### Form Validation
```bash
agent-browser fill @e5 "invalid"
agent-browser click @e6  # Submit
agent-browser wait --text "Invalid email"
agent-browser screenshot validation-error.png
```

### Modal/Dialog
```bash
agent-browser click @e7  # Opens modal
agent-browser wait @e10  # Wait for modal element
agent-browser click @e11 # Confirm
agent-browser wait --load networkidle
```

## When to Use

✅ Use agent-browser for:
- E2E testing user journeys
- Verifying UI after implementation
- Taking screenshots for documentation
- Testing form validation
- Checking responsive behavior

❌ Don't use for:
- Unit tests (use vitest/jest/pytest/cargo test)
- API tests (use fetch/curl)
- Static analysis (use eslint/tsc/ruff/clippy)
