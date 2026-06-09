---
name: impeccable
description: Use when the user wants to design, redesign, shape, critique, audit, polish, clarify, distill, harden, optimize, adapt, animate, colorize, extract, or otherwise improve a frontend interface. Covers websites, landing pages, dashboards, product UI, app shells, components, forms, settings, onboarding, and empty states. Handles UX review, visual hierarchy, information architecture, cognitive load, accessibility, performance, responsive behavior, theming, anti-patterns, typography, fonts, spacing, layout, alignment, color, motion, micro-interactions, UX copy, error states, edge cases, i18n, and reusable design systems or tokens. Also use for bland designs that need to become bolder or more delightful, loud designs that should become quieter, live browser iteration on UI elements, or ambitious visual effects that should feel technically extraordinary. Not for backend-only or non-UI tasks.
version: 3.5.0
user-invocable: true
argument-hint: "[craft|shape · audit|critique · animate|bolder|colorize|delight|layout|overdrive|quieter|typeset · adapt|clarify|distill · harden|onboard|optimize|polish · init|document|extract|live] [target]"
license: Apache 2.0
---

Designs and iterates production-grade frontend interfaces. Real working code, committed design choices, exceptional craft.

## Design guidance

Produce ready-to-ship, production-grade code, not prototypes or starting points. Don't stop until arriving at a complete implementation (beautiful, responsive, fast, precise, bug-free, on brand).

### General rules

#### Color

- **Verify contrast.** Body text must hit ≥4.5:1 against its background; large text (≥18px or bold ≥14px) needs ≥3:1. Placeholder text needs the same 4.5:1.
- Gray text on a colored background looks washed out. Use a darker shade of the background's own hue, or a transparency of the text color.

#### Typography

- Cap body line length at 65–75ch.
- Hierarchy through scale + weight contrast (≥1.25 ratio between steps).
- Cap font-family count at 3 (display + body + optional mono).
- Don't pair fonts that are similar (two geometric sans-serifs). Pair on a contrast axis.
- No all-caps body copy.
- Hero / display heading ceiling: clamp() max ≤ 6rem (~96px).
- Use `text-wrap: balance` on h1–h3; `text-wrap: pretty` on long prose.

#### Layout

- Vary spacing for rhythm.
- Cards are the lazy answer. Use them only when they're truly the best affordance. Nested cards are always wrong.
- Flexbox for 1D, Grid for 2D.
- For responsive grids without breakpoints: `repeat(auto-fit, minmax(280px, 1fr))`.
- Build a semantic z-index scale (dropdown → sticky → modal-backdrop → modal → toast → tooltip).

#### Motion

- Motion should be intentional.
- Don't animate CSS layout properties unless truly needed.
- Ease out with exponential curves (ease-out-quart / quint / expo). No bounce, no elastic.
- Reduced motion is not optional. Every animation needs a `@media (prefers-reduced-motion: reduce)` alternative.
- Reveal animations must enhance an already-visible default. Don't gate content visibility on a class-triggered transition.

#### Interaction

- Dropdowns rendered with `position: absolute` inside an `overflow: hidden` container will be clipped. Use `position: fixed` or a portal to escape the stacking context.

### Copy

- Every word earns its place.
- **No em dashes.** Use commas, colons, semicolons, periods, or parentheses.
- **No marketing buzzwords.** streamline / empower / supercharge / leverage / unleash / transform / seamless / world-class. Pick a specific noun and verb.
- Button labels: verb + object. "Save changes" beats "OK"; "Delete project" beats "Yes".
- Link text needs standalone meaning.

### Absolute bans

- **Side-stripe borders.** `border-left` or `border-right` > 1px as a colored accent on cards or callouts. Rewrite with full borders, background tints, or nothing.
- **Gradient text.** `background-clip: text` with a gradient. Use a single solid color.
- **Glassmorphism as default.** Blurs and glass cards used decoratively.
- **The hero-metric template.** Big number, small label, supporting stats, gradient accent. SaaS cliché.
- **Identical card grids.** Same-sized cards with icon + heading + text, repeated endlessly.
- **Tiny uppercase tracked eyebrow above every section.** One named kicker as deliberate brand system is voice; an eyebrow on every section is AI grammar.
- **Numbered section markers as default scaffolding (01 / 02 / 03).** Numbers earn their place only when the section actually IS a sequence.
- **Text that overflows its container.** Test heading copy at every breakpoint.

### Color for new projects

- Use OKLCH.
- The cream/sand/beige body bg is the saturated AI default. If the brief is "warm", carry warmth via accent + typography + imagery, not bg color.
- Tinted neutrals: add 0.005–0.015 chroma toward the brand's hue.
- Dark vs. light is never a default. Before choosing, write one sentence of physical scene: who uses this, where, under what light, in what mood.

### The AI slop test

If someone could look at this interface and say "AI made that" without doubt, it's failed.

## Commands

| Command | Category | Description |
|---|---|---|
| `craft [feature]` | Build | Shape, then build a feature end-to-end |
| `shape [feature]` | Build | Plan UX/UI before writing code |
| `init` | Build | Set up project context: PRODUCT.md, DESIGN.md, live config, next steps |
| `document` | Build | Generate DESIGN.md from existing project code |
| `extract [target]` | Build | Pull reusable tokens and components into design system |
| `critique [target]` | Evaluate | UX design review with heuristic scoring |
| `audit [target]` | Evaluate | Technical quality checks (a11y, perf, responsive) |
| `polish [target]` | Refine | Final quality pass before shipping |
| `bolder [target]` | Refine | Amplify safe or bland designs |
| `quieter [target]` | Refine | Tone down aggressive or overstimulating designs |
| `distill [target]` | Refine | Strip to essence, remove complexity |
| `harden [target]` | Refine | Production-ready: errors, i18n, edge cases |
| `onboard [target]` | Refine | Design first-run flows, empty states, activation |
| `animate [target]` | Enhance | Add purposeful animations and motion |
| `colorize [target]` | Enhance | Add strategic color to monochromatic UIs |
| `typeset [target]` | Enhance | Improve typography hierarchy and fonts |
| `layout [target]` | Enhance | Fix spacing, rhythm, and visual hierarchy |
| `delight [target]` | Enhance | Add personality and memorable touches |
| `overdrive [target]` | Enhance | Push past conventional limits |
| `clarify [target]` | Fix | Improve UX copy, labels, and error messages |
| `adapt [target]` | Fix | Adapt for different devices and screen sizes |
| `optimize [target]` | Fix | Diagnose and fix UI performance |
| `live` | Iterate | Visual variant mode: pick elements in the browser, generate alternatives |
