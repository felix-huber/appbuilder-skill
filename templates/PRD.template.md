# 01 — PRD (Product Requirements)

## Summary
- **What we are building**: …
- **Why now**: …

## Goals
- …

## Non-goals
- …

## Users & Jobs-to-be-Done
### Persona A: [Name]
- **Job**: …
- **Pain**: …
- **Desired outcome**: …

### Persona B: [Name]
- …

## User Stories (with Acceptance Criteria)

### Story 1: [Title]
As a [persona], I want to [action] so that [outcome].

**Acceptance Criteria**
- [ ] Given [context], when [action], then [result]
- [ ] Given [context], when [action], then [result]

**Edge Cases**
- What if [condition]? → [behavior]

**E2E Test Scenario** (these become dedicated test beads)
```gherkin
Scenario: [Happy path name]
  Given [initial state]
  When [user action]
  Then [expected result]

Scenario: [Error case name]  
  Given [initial state]
  When [invalid action]
  Then [error message shown]
```

### Story 2: [Title]
…

## Functional Requirements
- FR1: …
- FR2: …

## UX Requirements (High Level)
- **Key screens**: …
- **Key flows**: …
- **Error states**: Must be explicit for every action.

## Data & Persistence
- What data is stored?
- Where? (local, server, both)
- Schema considerations?

## Security / Privacy
- Authentication requirements
- Authorization model
- Data sensitivity

## Observability
- **Events**: …
- **Metrics**: …
- **Logs**: …

## Rollout / Compatibility
- Feature flags needed?
- Migration plan?
- Backwards compatibility?

## Out of Scope
- …

## Open Questions
- …
