---
target: docs hierarchy redesign
total_score: 35
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 1
timestamp: 2026-08-13T12-29-58Z
slug: apps-docs-app-docs-slug-page-tsx
---
## Design Health Score

| Heuristic | Score | Note |
|---|---:|---|
| Visibility of system status | 3/4 | Page title, actions and TOC establish the current reading state. |
| Match system and real world | 4/4 | The content structure maps directly to the package architecture. |
| User control and freedom | 3/4 | Sidebar and links support navigation; article-to-article shortcuts can improve. |
| Consistency and standards | 4/4 | One route-owned H1 now anchors every page. |
| Error prevention | 3/4 | Installation and analyzer guidance are separated by purpose. |
| Recognition over recall | 4/4 | Cards, headings and TOC make the content scannable. |
| Flexibility and efficiency | 3/4 | Search and copy/open actions help, but next steps are not always explicit. |
| Aesthetic and minimalist design | 4/4 | Removing repeated headings materially reduces noise. |
| Error recovery | 3/4 | Troubleshooting content exists but could be linked more consistently. |
| Help and documentation | 4/4 | The docs provide detailed conceptual and practical coverage. |

Total: 35/40.

## Design specificity

The documentation is specific to better_effect because its hierarchy follows Effects, Modules, runtimes and packages. The wrapper title is now the single source of truth instead of competing with MDX headings.

## Priority issues

- **P1 — Chapter progression:** add a consistent next-step block at the end of Getting Started and long guides.
- **P2 — Internal orientation:** nested pages retain a compact folder breadcrumb; section index pages intentionally omit it to avoid a repeated current title.
- **P2 — Power-user navigation:** expose package and guide shortcuts near the article action row for fast scanning.

## Persona red flags

- First-time readers may need a stronger “you are here / next” signal after opening a deep page.
- Power users have search and copy actions, but no explicit previous/next chapter affordance.

## Questions

- What is the one next page a reader should open after each conceptual chapter?
- Should package pages expose a compact API surface summary before the long explanation?
