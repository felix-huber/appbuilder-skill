# /sprint — Generate Atomic Sprint Tasks from Spec

## Goal
Break down a project spec into atomic, committable tasks organized into demoable sprints. Generates tasks that can be loaded into beads_rust (br) or task-graph.json.

## Prerequisites
- A spec or PRD document (e.g., `docs/spec.md`, `artifacts/01-prd.md`)
- For beads output: `br` CLI installed (`cargo install --git https://github.com/Dicklesworthstone/beads_rust.git`)
- For task-graph output: `artifacts/03-plan.md` to compile

## Usage

```bash
# Analyze spec and generate sprint plan (markdown output)
/sprint docs/spec.md

# Generate directly as beads commands
/sprint docs/spec.md --beads

# Generate as task-graph format (plan.md style)
/sprint docs/spec.md --graph
```

## The Prompt

When given a spec document, use this prompt pattern (based on Doodlestein's methodology):

---

### Phase 1: Sprint Decomposition

```
@{spec_file}

Break this project down into sprints and tasks:

REQUIREMENTS:
- Every task/ticket should be an ATOMIC, committable piece of work with tests
  (or if tests don't make sense, another form of validation)
- Every sprint should result in a DEMOABLE piece of software that can be run,
  tested, and built on top of previous work/sprints
- Be exhaustive, clear, and technical
- Focus on small atomic tasks that compose into a clear goal for the sprint

OUTPUT FORMAT:
For each sprint:
  ## Sprint N: [Goal Name]
  **Demo:** [What can be demonstrated after this sprint]
  **Duration:** [Estimated time]
  
  ### Tasks:
  - [ ] task-tag :: Task title
    - **ID:** S{sprint}-T{task}
    - **Blocked by:** [dependencies]
    - **Verification:** [how to verify completion]
    - **Deliverable:** [concrete output]

GUIDELINES:
- Sprint 1 should establish foundation (project setup, core types, basic structure)
- Each subsequent sprint adds a complete, testable feature layer
- Tasks within a sprint can have internal dependencies
- Cross-sprint dependencies should be minimized
```

---

### Phase 2: Self-Review

After generating the sprint plan, invoke a subagent to review:

```
Review this sprint plan critically:

1. Are all tasks truly atomic and committable?
2. Is each sprint demoable on its own?
3. Are dependencies correctly identified?
4. Are verification steps concrete and testable?
5. Are there any gaps or missing tasks?
6. Is the ordering optimal for parallel work?

Suggest specific improvements.
```

---

### Phase 3: Output Generation

Based on the output format requested:

#### For Beads (--beads)

Generate shell commands:

```bash
# Sprint 1: Foundation
br create "Sprint 1: Foundation" -t epic -p 1 --json
SPRINT1=$(br list --json | jq -r '.[-1].id')

br create "Set up project structure" -t task -p 1 --parent $SPRINT1 --json
br create "Define core types" -t task -p 1 --parent $SPRINT1 --json

# Add dependencies
br dep add bd-task-2 bd-task-1  # types depends on structure
```

#### For Task Graph (--graph)

Generate plan.md format:

```markdown
## Sprint 1: Foundation

- [ ] setup, core :: Set up project structure
  - **ID:** S1-T1
  - **Verification:** `npm run build` succeeds
  - **Deliverable:** package.json, tsconfig.json, basic folder structure

- [ ] types, core :: Define core types
  - **ID:** S1-T2
  - **Blocked by:** S1-T1
  - **Verification:** `npm run typecheck` passes
  - **Deliverable:** src/types/index.ts with core interfaces
```

## Example Output

### Input: A todo app spec

### Output:

```markdown
## Sprint 1: Foundation
**Demo:** Empty app shell with build system working
**Duration:** 2-4 hours

### Tasks:
- [ ] setup, core :: Initialize project with Vite + React + TypeScript
  - **ID:** S1-T1
  - **Verification:** `npm run dev` starts, shows blank page
  - **Deliverable:** package.json, vite.config.ts, src/main.tsx

- [ ] types, core :: Define Todo and TodoList interfaces
  - **ID:** S1-T2
  - **Blocked by:** S1-T1
  - **Verification:** `npm run typecheck` passes
  - **Deliverable:** src/types/todo.ts

- [ ] state, core :: Create TodoStore with Zustand
  - **ID:** S1-T3
  - **Blocked by:** S1-T2
  - **Verification:** Unit tests pass for add/remove/toggle
  - **Deliverable:** src/stores/todoStore.ts + tests

## Sprint 2: Core UI
**Demo:** Can add, view, and toggle todos (no persistence)
**Duration:** 4-6 hours

### Tasks:
- [ ] ui, components :: Create TodoItem component
  - **ID:** S2-T1
  - **Blocked by:** S1-T3
  - **Verification:** Storybook story works, a11y checks pass
  - **Deliverable:** src/components/TodoItem.tsx + story

- [ ] ui, components :: Create TodoList component
  - **ID:** S2-T2
  - **Blocked by:** S2-T1
  - **Verification:** Renders list of TodoItems
  - **Deliverable:** src/components/TodoList.tsx + story

- [ ] ui, components :: Create AddTodo form
  - **ID:** S2-T3
  - **Blocked by:** S1-T3
  - **Verification:** Form submits, todo appears in store
  - **Deliverable:** src/components/AddTodo.tsx + tests
```

## Integration with Ralph

After generating sprints:

1. **For beads:** Run the generated `br` commands, then:
   ```bash
   ./scripts/ralph.sh --beads 50
   ```

2. **For task-graph:** Save to `artifacts/03-plan.md`, then:
   ```bash
   npm run tasks
   ./scripts/ralph.sh 50
   ```

## Tips

- **Keep tasks small:** If a task takes more than 2-4 hours, break it down
- **Test everything:** Every task should have a verification step
- **Demo often:** Each sprint should produce visible progress
- **Dependencies matter:** Be explicit about what blocks what
- **Use tags:** Help with smart routing (ui, backend, core, tests, etc.)

## Related Commands

- `/plan` - Generate implementation plan
- `/artifact-tasks` - Compile plan to task-graph.json
- `/ralph` - Run autonomous execution loop
