# 02 — UX Spec (Flows + State)

## Design Direction
- **Principles**:
  1. …
  2. …
  3. …
- **Tasteboard link**: artifacts/05-design/tasteboard.md

## User Journeys (E2E Test Basis)

Define complete user journeys. Mark happy paths with ⭐ — these are tested on every build.

### UJ-001: [Journey Name] ⭐ HAPPY PATH
**Goal:** What the user wants to accomplish
**Frequency:** Daily / Weekly / Rare
**Priority:** P0 (must work) / P1 (important) / P2 (nice-to-have)

**Steps:**
1. User [action]
   - **Sees:** [UI elements]
   - **State:** [Loading / Empty / Loaded]
   
2. User [action]
   - **Sees:** [result]
   - **Validation:** [if input]
   
3. User [action]
   - **Success:** [outcome]
   - **Error:** [handling]

**E2E Test (agent-browser):**
```bash
agent-browser open http://localhost:3000
agent-browser snapshot -i
agent-browser click @e2        # [describe element]
agent-browser fill @e5 "data"  # [describe field]
agent-browser click @e8        # Submit
agent-browser wait --text "Success"
agent-browser screenshot uj-001.png
```

### UJ-002: [Journey Name] ⭐ HAPPY PATH
…

### UJ-003: [Journey Name]
(Non-happy path, tested less frequently)
…

## Primary Flows

### Flow A: [Name]
**Trigger**: User wants to [goal]

**Steps**:
1. User [action] → System [response]
2. User [action] → System [response]
3. …

**Success state**: [What user sees when done]

**Error paths**:
- If [condition] → Show [error], allow [recovery]

### Flow B: [Name]
…

## Screen Inventory

| Screen | Purpose | Entry points |
|--------|---------|--------------|
| Screen 1 | … | … |
| Screen 2 | … | … |

## State Matrix (per screen)

### Screen 1: [Name]

| State | What user sees | Available actions | Telemetry |
|-------|----------------|-------------------|-----------|
| **Loading** | Spinner + "Loading..." | Cancel | `screen1_loading` |
| **Empty** | Empty state + CTA | [Primary action] | `screen1_empty` |
| **Error (recoverable)** | Error + Retry | Retry, Cancel | `screen1_error` |
| **Error (fatal)** | Error + Support | Contact support | `screen1_fatal` |
| **Success** | Content displayed | [All actions] | `screen1_loaded` |

### Screen 2: [Name]
…

## Validation & Copy Rules

| Field | Validation | Error copy |
|-------|------------|------------|
| Email | RFC 5322 | "Please enter a valid email" |
| Password | Min 8, 1 number | "Password needs 8+ chars and a number" |

## Accessibility Expectations
- **Keyboard nav**: All interactive elements focusable
- **Screen reader**: ARIA labels on icons
- **Contrast**: WCAG AA (4.5:1)
- **Motion**: Respect `prefers-reduced-motion`

## Responsive Breakpoints

| Breakpoint | Width | Layout |
|------------|-------|--------|
| Mobile | < 640px | Single column |
| Tablet | 640-1024px | Two columns |
| Desktop | > 1024px | Three columns |
