# 03 — Implementation Plan

## Architecture Overview

### System Diagram
```mermaid
flowchart TB
    subgraph Client
        UI[UI Layer]
        State[State Management]
    end
    
    subgraph Backend
        API[API Layer]
        DB[Database]
    end
    
    UI --> State
    State --> API
    API --> DB
```

### Modules/Components
| Module | Responsibility | Dependencies |
|--------|---------------|--------------|
| … | … | … |

### Data Model
```typescript
interface Entity {
  id: string;
  // ...
}
```

### API Contracts (if any)
- `POST /api/...` — …
- `GET /api/...` — …

## Test Strategy

### Test Layers
| Layer | Scope | Location | Written |
|-------|-------|----------|---------|
| Unit | Individual functions/classes | `*.test.ts` next to source | With feature (TDD) |
| Integration | API contracts, module interactions | `tests/integration/` | Separate bead |
| E2E | Full user flows | `e2e/` | Separate bead |

### Unit Test Contracts (TDD - per module)
For each module, define the test contract that agents write FIRST:

**Module: [name]**
```typescript
describe('[ModuleName]', () => {
  it('[expected behavior]')
  it('[edge case]')
  it('[error handling]')
})
```

### Integration Test Contracts
| Component A | Component B | Contract | Test |
|-------------|-------------|----------|------|
| Form | API | onSubmit calls createItem() | form-api.test.ts |
| API | Store | success updates items array | api-store.test.ts |

### E2E Scenarios (from PRD acceptance criteria)
| User Story | Scenario | Expected | Priority |
|------------|----------|----------|----------|
| … | … | … | P1 |

## Key Technical Decisions

### Decision 1: [Topic]
- **Choice**: …
- **Why**: …
- **Alternatives**: …
- **Trade-offs**: …

### Decision 2: [Topic]
…

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| … | Medium | High | … |

## Task Seeds

### Task Atomicity Principles (from jdrhyne/planner)

Each task MUST be:
- **Atomic and committable** — small, independent pieces of work
- **Specific and actionable** — not vague
- **Testable** — include verification method
- **Located** — include file paths

**❌ Bad Task:**
- [ ] <auth> :: Implement Google OAuth

**✅ Good Tasks (broken down):**
- [ ] <auth,config> :: Add Google OAuth environment variables
- [ ] <auth,deps> :: Install passport-google-oauth20 package
- [ ] <auth,api> :: Create OAuth callback route handler
- [ ] <auth,ui> :: Add Google sign-in button to login page

### Sprint Structure

Each sprint must:
- Result in a **demoable, runnable, testable increment**
- Build on prior sprint work
- Include **demo/validation checklist**

Use this **exact format** (parsed by task compiler):

### Sprint 1: [Sprint Name]

**Goal**: [What this sprint accomplishes]

**Demo/Validation**:
- [ ] How to run/demo this sprint's output
- [ ] What to verify

**Tasks**:

- [ ] <tag1,tag2> :: Task subject here
      - Description: What needs to be done
      - Deliverable: What artifact is produced
      - Files: src/path/file.ts, src/other/file.ts
      - Allowed paths: src/path/*, src/other/*
      - Unit Test Specs: (for feature tasks) List specific tests to write first
      - Verification: npm run test (or other command)
      - Complexity: 1-10 (perceived difficulty)
      - DependsOn: (optional) S1-T1, S1-T2

### Example Sprint:

### Sprint 1: Core Foundation

**Goal**: Setup project structure and core types

**Demo/Validation**:
- [ ] `npm run dev` starts without errors
- [ ] TypeScript compiles with no errors
- [ ] Core types are importable

**Tasks**:

- [ ] <setup,core> :: Initialize project structure
      - Description: Create Vite + React + TypeScript scaffold
      - Deliverable: package.json, tsconfig.json, vite.config.ts
      - Files: package.json, tsconfig.json, vite.config.ts
      - Allowed paths: /
      - Verification: npm run dev starts
      - Complexity: 2

- [ ] <core,types> :: Define core data types
      - Description: Create TypeScript interfaces for database, table, column
      - Deliverable: src/types/index.ts with Database, Table, Column types
      - Files: src/types/index.ts
      - Allowed paths: src/types/*
      - Unit Test Specs: isDatabase() returns true for valid db; isTable() validates required fields; serialization round-trips correctly
      - Verification: npm run test -- types && tsc --noEmit
      - Complexity: 3
      - DependsOn: S1-T1

## Verification Plan

### Local Development
```bash
npm install
npm run dev
```

### E2E Flows to Test
1. [ ] User can [primary action]
2. [ ] User can [secondary action]
3. [ ] Error states display correctly

### Regression Checklist
- [ ] All unit tests pass
- [ ] All E2E tests pass
- [ ] No console errors
- [ ] Bundle size < X KB

## Rollout Plan
- **Feature flags**: …
- **Monitoring**: …
- **Rollback**: …

## Open Questions
- …
