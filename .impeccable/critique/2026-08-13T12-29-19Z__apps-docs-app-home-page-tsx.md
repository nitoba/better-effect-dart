---
target: landing and docs hierarchy redesign
total_score: 30
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 2
timestamp: 2026-08-13T12-29-19Z
slug: apps-docs-app-home-page-tsx
---
## Design Health Score

| Heuristic | Score | Note |
|---|---:|---|
| Visibility of system status | 2/4 | The hero proof panel communicates ready/runtime state, but docs navigation can be stronger. |
| Match system and real world | 4/4 | Effect, Module and Runtime are represented with product-specific language. |
| User control and freedom | 3/4 | Primary and documentation paths are clear. |
| Consistency and standards | 4/4 | Landing and docs share a coherent visual grammar. |
| Error prevention | 3/4 | Typed failures and explicit composition are clearly surfaced. |
| Recognition over recall | 3/4 | The architecture rail makes the core model recognizable. |
| Flexibility and efficiency | 2/4 | Long docs still need stronger next-step navigation. |
| Aesthetic and minimalist design | 3/4 | The hero is focused; dense mobile content remains a watch point. |
| Error recovery | 2/4 | Recovery guidance belongs in the documentation flow. |
| Help and documentation | 4/4 | The content structure, cards and guides are strong. |

Total: 30/40.

## Design specificity

The split hero, architecture rail and typed Dart terminal are authored for better_effect rather than a generic SaaS template. Removing the full-width banner from behind the headline restores contrast and makes the product proof legible.

## Strengths

- The first viewport now has a clear left-to-right reading order: promise, explanation, action, proof.
- The docs route owns the single page H1; duplicate MDX H1s were removed, and section pages retain useful path context without repeating their title.
- The lower CTA is an execution diagram, so it reinforces the product model instead of introducing another decorative hero.

## Priority issues

- **P1 — Mobile density:** the title, metadata, terminal and architecture cues still compete on narrow screens. Keep the rail hidden on mobile and consider a shorter code sample if testing shows scroll pressure.
- **P1 — Deep-doc orientation:** keep a compact breadcrumb for internal pages and add a “next step” block to long chapters.
- **P2 — Progression:** link the end of Getting Started to the first package guide and the end of package guides to the analyzer/Flutter path.

## Persona red flags

- First-time readers may need to decode Effect/Module/Runtime before understanding the promise; the supporting copy should remain visible beside the hero.
- Mobile readers may find the terminal sample too small; prioritize the first three meaningful lines if truncation is needed.
- Power users have no explicit chapter-to-chapter shortcut at the end of long docs pages.

## Questions

- Should the landing prioritize a faster product promise or teach the architecture model before the first click?
- Would a persistent “next step” pattern make the docs journey feel more intentional than a clean but isolated article?
