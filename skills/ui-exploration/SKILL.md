---
name: ui-exploration
description: Guide UI design exploration using tasteboard for references, keystone for primary screen, and variants for alternatives. Use when exploring design direction, creating UI mockups, or generating HTML prototypes.
triggers:
  - tasteboard
  - design exploration
  - ui variants
  - keystone
  - design direction
  - visual reference
  - ui mockup
  - html prototype
---

# UI Exploration Skill

Guide the UI design exploration process from inspiration gathering to final direction.

## ⚠️ CHECK EXISTING STATE FIRST

**Before starting UI exploration, check what already exists:**

```bash
# Check existing design artifacts
ls -la artifacts/05-design/ 2>/dev/null
ls -la artifacts/05-design/variants/ 2>/dev/null

# Check for tasteboard
cat artifacts/05-design/tasteboard.md 2>/dev/null | head -20

# Check for keystone
ls -la artifacts/05-design/keystone.html 2>/dev/null

# Check manifest
cat artifacts/05-design/manifest.json 2>/dev/null | jq '.screens | length'
```

| Situation | Action |
|-----------|--------|
| No design artifacts | → Start from Phase 1 (Tasteboard) |
| Tasteboard exists, no keystone | → Skip to Phase 2 (Keystone) |
| Keystone exists, no variants | → Skip to Phase 3 (Variants) |
| All artifacts exist | → Review and refine if needed |

---

## Overview

UI exploration follows this flow:
```
Tasteboard (references) → Keystone (primary) → Variants (alternatives) → Converge
```

## Phase 1: Tasteboard

### Purpose
Collect visual references that define the design direction.

### Categories
- **Typography**: Font combinations, hierarchy, scale
- **Color**: Palettes, themes, contrast approaches
- **Layout**: Grids, spacing, composition
- **Components**: Buttons, cards, forms, navigation
- **Animation**: Motion patterns, transitions, micro-interactions
- **Inspiration**: Full-page examples from admired products

### Using the Tasteboard Tool
```bash
npm run tasteboard
# Open http://localhost:8080/tools/tasteboard/
```

Guide user to add 15-25 references across categories.

### Export
Click "Export Markdown" → save to `artifacts/05-design/tasteboard.md`

### Synthesize Principles
Extract 3-5 design principles from the tasteboard:

```markdown
## Design Principles

1. **Clarity over decoration**: Every element serves a purpose
2. **Generous whitespace**: Let content breathe
3. **Subtle motion**: Animations enhance, never distract
4. **Dark-first**: Optimized for focus and reduced eye strain
5. **Responsive by default**: Mobile experience is not an afterthought
```

## Phase 2: Keystone Screen

### Purpose
Create the most important screen as the foundation for all others.

### Identifying the Keystone
The keystone is typically:
- The main workspace or editor
- The primary dashboard
- The core interaction surface
- Where users spend most time

### Keystone Requirements
- Uses principles from tasteboard
- Shows realistic content (not "Lorem ipsum")
- Includes all states from UX spec (at least success state)
- Is responsive
- Uses modern CSS (Tailwind recommended)

### Template
```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>[App] — [Screen Name]</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <style>
    /* Custom properties from tasteboard */
    :root {
      --color-primary: #...;
      --color-surface: #...;
      --font-display: '...', sans-serif;
    }
    
    /* Custom styles */
  </style>
</head>
<body class="bg-[var(--color-surface)] text-white">
  <!-- Navigation -->
  <nav>...</nav>
  
  <!-- Main content -->
  <main>...</main>
  
  <!-- Footer/Status -->
  <footer>...</footer>
</body>
</html>
```

## Phase 3: Variants

### Purpose
Explore alternatives to find the best direction.

### Variant Dimensions

| Dimension | Variants |
|-----------|----------|
| Theme | Light, Dark, Auto |
| Density | Minimal, Comfortable, Dense |
| Personality | Professional, Playful, Neutral |
| Layout | Single column, Split, Three-panel |
| Navigation | Top, Side, Bottom |

### Recommended Variants
Generate 6-12 variants exploring different combinations:

1. `variant-01-dark.html` — Dark theme (baseline)
2. `variant-02-light.html` — Light theme
3. `variant-03-minimal.html` — Extreme minimalism
4. `variant-04-rich.html` — Information-dense
5. `variant-05-playful.html` — Rounded, colorful
6. `variant-06-corporate.html` — Sharp, professional
7. `variant-07-mobile-first.html` — Mobile-optimized
8. `variant-08-split.html` — Split-panel layout
9. `variant-09-sidebar.html` — Persistent sidebar
10. `variant-10-bottom-nav.html` — Mobile-style bottom nav

### Variant Guidelines
- Each variant should be noticeably different
- Don't just change colors—change structure, spacing, typography
- Make bold choices; refinement comes later
- Include realistic content

## Phase 4: Design Gallery

### Purpose
Compare variants side-by-side to select direction.

### Using the Gallery
```bash
# Build manifest first
node scripts/design_manifest_build.js

# Start gallery
npm run gallery
# Open http://localhost:8080/tools/design-gallery/
```

### Evaluation Criteria
Rate each variant on:
- [ ] Clarity: Is the interface easy to understand?
- [ ] Focus: Does it support the primary use case?
- [ ] Aesthetics: Does it feel polished and intentional?
- [ ] Responsiveness: Does it work at all sizes?
- [ ] Consistency: Does it feel cohesive?

### Selection Process
1. Eliminate variants that don't work
2. Identify top 2-3 candidates
3. Note elements to borrow from runners-up
4. Select primary direction

## Phase 5: Convergence

### Update Keystone
Incorporate selected elements:
- Theme from chosen variant
- Layout patterns that work
- Typography scale
- Component styles
- Animation patterns

### Document Decisions
Add to `artifacts/05-design/tasteboard.md`:

```markdown
## Final Direction

**Selected**: variant-03-minimal.html

**Key decisions**:
- Dark theme with #0a0a0a background
- SF Mono for code, Inter for UI text
- 8px spacing grid
- Rounded corners (8px default)
- Subtle fade transitions (150ms)

**Borrowed from other variants**:
- Card shadow style from variant-05-playful
- Navigation pattern from variant-09-sidebar
```

### Outputs
- `artifacts/05-design/tasteboard.md` — Updated with decisions
- `artifacts/05-design/keystone.html` — Final keystone
- `artifacts/05-design/variants/` — All variants for reference
- `artifacts/05-design/manifest.json` — Gallery manifest

## Integration with UX Spec

After convergence, update UX spec if needed:
- Specific component names
- Exact copy/validation messages
- Animation specifications
- Responsive breakpoint behaviors

Consider re-running `/oracle ux` after design decisions.
