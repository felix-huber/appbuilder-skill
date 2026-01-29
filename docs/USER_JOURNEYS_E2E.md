# User Journeys & E2E Testing Guide

## Why User Journeys?

User journeys document the **complete path** a user takes to accomplish a goal. 
They're more comprehensive than user stories and directly map to E2E tests.

**Key insight from the community:**
> "Before you build, I would highly recommend building a MD file that has all your user journeys. 
> Define which user journeys are the happy path (meaning the most used). 
> And make sure that it tests those happy path user journeys at the end of each build using E2E testing."

## User Journey Format

Add this section to `artifacts/02-ux.md`:

```markdown
## User Journeys

### UJ-001: [Journey Name] ⭐ HAPPY PATH
**Goal:** What the user wants to accomplish
**Frequency:** Daily / Weekly / Rare
**Priority:** P0 (critical) / P1 (important) / P2 (nice-to-have)

#### Steps
1. User opens the app
   - **Sees:** Landing page with [elements]
   - **State:** Initial / Empty
   
2. User clicks [button]
   - **Sees:** [result]
   - **State:** Loading → Loaded
   
3. User enters [data]
   - **Validation:** [rules]
   - **Error states:** [what could go wrong]

4. User submits
   - **Success:** [what happens]
   - **Error:** [error handling]

#### E2E Test Scenario
```gherkin
Feature: [Journey Name]
  Scenario: Happy path
    Given I am on the landing page
    When I click "Get Started"
    And I fill in "email" with "test@example.com"
    And I click "Submit"
    Then I should see "Welcome!"
```

#### agent-browser Commands
```bash
agent-browser open http://localhost:3000
agent-browser snapshot -i
agent-browser click @e2  # "Get Started" button
agent-browser fill @e5 "test@example.com"
agent-browser click @e8  # Submit
agent-browser wait --text "Welcome!"
agent-browser screenshot uj-001-complete.png
```
```

## Happy Path Definition

**Happy paths** (marked with ⭐) are:
- The most common user flows (>80% of usage)
- Must work perfectly
- Tested on every build
- Used for demo/showcase

**Non-happy paths** are:
- Edge cases
- Error recovery flows
- Admin/power user flows
- Tested less frequently

## Test Quality Guardrails (No Fake Tests)
Fake/tautological tests are unacceptable. **BLOCKER** if tests:
- Assert only hardcoded/config values
- Never perform real actions (no click/command/request -> no state change)
- Bypass the system under test via excessive mocking
- Verify only selectors/IDs without checking UI state changes

Every test must include at least one **behavioral** assertion:
- UI/E2E: perform action + assert visible state change
- API: make real request + assert response + persistence or side effect
- CLI: run command + assert exit code/output + side effects
- Library: call public API + assert state/output change

If a feature isn't fully integrated yet, add a harness (below) so tests are real.
Run a **test quality review** (fresh-eyes or cross-model) focused on detecting fake tests.

## Integration with Oracle Swarm

### In /ux Command
Add User Journeys section after Screen Inventory:

```markdown
## User Journeys

### UJ-001: Create New Database ⭐ HAPPY PATH
**Goal:** User creates a new SQLite database from scratch
**Frequency:** Every session start
**Priority:** P0

#### Steps
1. User opens app
   - Sees: Empty state with "Create Database" CTA
   
2. User clicks "Create Database"
   - Sees: Database created, empty table list
   
3. User clicks "New Table"
   - Sees: Table creation dialog

#### E2E Test
```bash
agent-browser open http://localhost:5173
agent-browser snapshot -i
agent-browser click @e3  # Create Database
agent-browser wait --text "Tables"
agent-browser screenshot uj-001-success.png
```

### UJ-002: Import Existing Database ⭐ HAPPY PATH
...

### UJ-003: Run SQL Query ⭐ HAPPY PATH
...

### UJ-004: Export Data (Non-happy path)
...
```

### In /gates Command
After implementation, run E2E tests for happy paths:

```bash
# Run all happy path E2E tests
./scripts/run_e2e_happy_paths.sh
```

## Test Harness Patterns (when full integration isn't ready)
If core flows/components aren't integrated yet, add a harness so tests exercise
real behavior:

- **UI apps**: minimal route/screen that renders the real component with mock data
- **CLI tools**: fixture commands that read/write temp dirs and verify side effects
- **APIs/services**: minimal runner that starts the server and hits real endpoints
- **Libraries**: a tiny example harness that calls public APIs end-to-end

The harness must make it possible to run **real** tests (not config-only assertions).

## agent-browser Integration

### Installation
```bash
npm install -g agent-browser
agent-browser install  # Downloads Chromium
```

### Usage in Ralph

Add to task verification:
```json
{
  "verification": [
    "npm run build",
    "npm run preview &",
    "sleep 3",
    "agent-browser open http://localhost:4173",
    "agent-browser snapshot -i",
    "agent-browser click @e2",
    "agent-browser wait --text 'Success'",
    "agent-browser screenshot e2e-proof.png"
  ]
}
```

### E2E Test Script Template

Create `scripts/run_e2e_happy_paths.sh`:

```bash
#!/bin/bash
set -e

echo "Starting E2E tests for happy paths..."

# Start dev server in background
npm run preview &
SERVER_PID=$!
sleep 5

# Trap to cleanup server
trap "kill $SERVER_PID 2>/dev/null" EXIT

# UJ-001: Create New Database
echo "Testing UJ-001: Create New Database..."
agent-browser open http://localhost:4173
agent-browser snapshot -i
agent-browser click @e3  # Create Database button
agent-browser wait --text "Tables" --timeout 5000
agent-browser screenshot artifacts/e2e/uj-001.png
echo "✅ UJ-001 passed"

# UJ-002: Import Database
echo "Testing UJ-002: Import Database..."
agent-browser reload
agent-browser snapshot -i
agent-browser click @e4  # Import button
agent-browser upload @e10 "test-fixtures/sample.db"
agent-browser wait --text "Tables"
agent-browser screenshot artifacts/e2e/uj-002.png
echo "✅ UJ-002 passed"

# UJ-003: Run SQL Query
echo "Testing UJ-003: Run SQL Query..."
agent-browser fill @e15 "SELECT * FROM users LIMIT 5"
agent-browser click @e16  # Run button
agent-browser wait --text "5 rows"
agent-browser screenshot artifacts/e2e/uj-003.png
echo "✅ UJ-003 passed"

echo ""
echo "═══════════════════════════════════════════"
echo "  ALL HAPPY PATH E2E TESTS PASSED ✅"
echo "═══════════════════════════════════════════"

agent-browser close
```

## Adding to Oracle Swarm Workflow

### Modified /ux Command

After generating UX spec, require User Journeys:

```
✅ UX spec generated: artifacts/02-ux.md

⚠️ IMPORTANT: Add User Journeys section!

Required for each journey:
- Goal
- Steps with expected UI states
- E2E test scenario (Gherkin or agent-browser)
- Mark happy paths with ⭐

Happy paths will be tested after each sprint.
```

### Modified /gates Command

Add E2E happy path testing:

```bash
# ... existing gates ...

# E2E Happy Path Tests
if [ -f "scripts/run_e2e_happy_paths.sh" ]; then
  echo "Running E2E happy path tests..."
  bash scripts/run_e2e_happy_paths.sh
  E2E_EXIT=$?
else
  echo "⚠️ No E2E tests found (scripts/run_e2e_happy_paths.sh)"
  E2E_EXIT=0
fi
```

## Summary

| Artifact | Contains |
|----------|----------|
| `artifacts/02-ux.md` | User Journeys with E2E scenarios |
| `scripts/run_e2e_happy_paths.sh` | Executable E2E tests |
| `artifacts/e2e/` | E2E test screenshots |
| `artifacts/07-verification.md` | E2E test results |

This ensures every build is verified against real user workflows, not just unit tests.
