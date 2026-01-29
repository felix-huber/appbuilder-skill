---
name: frontend-design
description: Expert frontend design guidelines for creating beautiful, modern UIs. Use when building landing pages, dashboards, or any user interface requiring polished design.
---

# Frontend Design Skill

Based on jdrhyne/agent-skills frontend-design and SuperDesign patterns.

## Design Workflow

Follow this structured approach for UI design:

1. **Layout Design** — Think through component structure, create ASCII wireframes
2. **Theme Design** — Define colors, fonts, spacing, shadows
3. **Animation Design** — Plan micro-interactions and transitions
4. **Implementation** — Generate the actual code

## 1. Layout Design (ASCII Wireframes)

**Before coding, sketch the layout in ASCII format:**

```
┌─────────────────────────────────────┐
│           HEADER / NAV              │
├─────────────────────────────────────┤
│                                     │
│           HERO SECTION              │
│         (Title + CTA)               │
│                                     │
├───────────┬───────────┬─────────────┤
│  FEATURE  │  FEATURE  │  FEATURE    │
│   CARD    │   CARD    │   CARD      │
├───────────┴───────────┴─────────────┤
│              FOOTER                 │
└─────────────────────────────────────┘
```

This ensures you think through structure before diving into code.

## 2. Theme Guidelines

### Color Rules

- **NEVER** use generic bootstrap-style blue (#007bff) — it looks dated
- Prefer `oklch()` for modern color definitions
- Use semantic color variables (--primary, --secondary, --muted)
- Consider both light and dark mode from the start

### Font Selection (Google Fonts)

| Type | Recommendations |
|------|-----------------|
| **Sans-serif** | Inter, Outfit, DM Sans, Space Grotesk, Plus Jakarta Sans |
| **Monospace** | JetBrains Mono, Fira Code, Geist Mono, Space Mono |
| **Serif** | Merriweather, Playfair Display, Source Serif Pro |
| **Display** | Architects Daughter, Oxanium |

### Spacing & Shadows

- Use consistent spacing scale (0.25rem base)
- Shadows should be subtle — avoid heavy drop shadows
- Consider using `oklch()` for shadow colors too

## 3. Theme Patterns

### Modern Dark Mode (Vercel/Linear style)

```css
:root {
  --background: oklch(0.145 0 0);
  --foreground: oklch(0.985 0 0);
  --primary: oklch(0.7 0.15 250);
  --primary-foreground: oklch(0.985 0 0);
  --muted: oklch(0.27 0 0);
  --muted-foreground: oklch(0.71 0 0);
  --border: oklch(0.27 0 0);
  --radius: 0.5rem;
  --font-sans: Inter, system-ui, sans-serif;
}
```

### Light Mode (Clean/Minimal)

```css
:root {
  --background: oklch(1 0 0);
  --foreground: oklch(0.145 0 0);
  --primary: oklch(0.55 0.2 250);
  --secondary: oklch(0.97 0 0);
  --muted: oklch(0.97 0 0);
  --muted-foreground: oklch(0.55 0 0);
  --border: oklch(0.92 0 0);
}
```

### Neo-Brutalism (90s revival)

```css
:root {
  --background: oklch(1 0 0);
  --foreground: oklch(0 0 0);
  --primary: oklch(0.65 0.24 27);
  --border: oklch(0 0 0);
  --radius: 0px;
  --shadow: 4px 4px 0px 0px hsl(0 0% 0%);
  --font-sans: DM Sans, sans-serif;
}
```

### Glassmorphism

```css
.glass {
  background: rgba(255, 255, 255, 0.1);
  backdrop-filter: blur(10px);
  border: 1px solid rgba(255, 255, 255, 0.2);
  border-radius: 1rem;
}
```

## 4. Animation Guidelines

### Micro-Syntax for Planning

Before implementing, plan animations with this syntax:

```
button:     150ms [S1→0.95→1] press
hover:      200ms [Y0→-2, shadow↗]
fadeIn:     400ms ease-out [Y+20→0, α0→1]
slideIn:    350ms ease-out [X-100→0, α0→1]
bounce:     600ms [S0.95→1.05→1]
```

### Timing Guidelines

| Animation Type | Duration |
|---------------|----------|
| Entry animations | 300-500ms, ease-out |
| Hover states | 150-200ms |
| Button press | 100-150ms |
| Page transitions | 300-400ms |

## 5. Component Design Tips

### Cards
- Subtle shadows, not heavy drop shadows
- Consistent padding (p-4 to p-6)
- Hover state: slight lift + shadow increase

### Buttons
- Clear visual hierarchy (primary, secondary, ghost)
- Adequate touch targets (min 44x44px)
- Loading and disabled states

### Forms
- Clear labels above inputs
- Visible focus states
- Inline validation feedback
- Adequate spacing between fields

### Navigation
- Sticky header for long pages
- Clear active state indication
- Mobile-friendly hamburger menu

## 6. Responsive Design

**Always design mobile-first:**

```css
/* Mobile first */
.container { padding: 1rem; }

/* Tablet (md) */
@media (min-width: 768px) {
  .container { padding: 2rem; }
}

/* Desktop (lg) */
@media (min-width: 1024px) {
  .container { 
    max-width: 1200px; 
    margin: 0 auto; 
  }
}
```

## 7. Accessibility

- Use semantic HTML (`header`, `main`, `nav`, `section`, `article`)
- Include proper heading hierarchy (h1 → h2 → h3)
- Add aria-labels to interactive elements
- Ensure sufficient color contrast (4.5:1 minimum)
- Support keyboard navigation

## 8. Quick Reference

| Element | Recommendation |
|---------|---------------|
| Primary font | Inter, Outfit, DM Sans |
| Code font | JetBrains Mono, Fira Code |
| Border radius | 0.5rem - 1rem (modern), 0 (brutalist) |
| Shadow | Subtle, 1-2 layers max |
| Spacing | 4px base unit (0.25rem) |
| Animation | 150-400ms, ease-out |
| Colors | oklch(), avoid generic blue |

## 9. CDN Resources

```html
<!-- Tailwind CSS -->
<script src="https://cdn.tailwindcss.com"></script>

<!-- Flowbite Components -->
<link href="https://cdn.jsdelivr.net/npm/flowbite@2.0.0/dist/flowbite.min.css" rel="stylesheet">
<script src="https://cdn.jsdelivr.net/npm/flowbite@2.0.0/dist/flowbite.min.js"></script>

<!-- Lucide Icons -->
<script src="https://unpkg.com/lucide@latest/dist/umd/lucide.min.js"></script>
<script>lucide.createIcons();</script>

<!-- Google Fonts -->
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
```

## 10. Image Placeholders

Use real placeholder services:
- **Unsplash**: `https://images.unsplash.com/photo-xxx?w=800&h=600`
- **Placehold.co**: `https://placehold.co/800x600`

**Never** make up image URLs.

## Source

Based on SuperDesign patterns — https://superdesign.dev
