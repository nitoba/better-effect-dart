# better_effect documentation

The documentation site is a Next.js application powered by Fumadocs and MDX.
It lives under `apps/docs` so it can evolve independently from the Dart
packages in `packages/`.

## Development

```bash
cd apps/docs
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000). Documentation pages are
under `content/docs`; navigation is defined by the `meta.json` files in each
section.

## Checks

```bash
npm run typecheck
npm run lint
npm run build
```

The app exposes Fumadocs search, Markdown/LLM routes, per-page OG images,
`robots.txt`, `sitemap.xml`, and a generated web manifest.

## Content conventions

- Write product documentation in Brazilian Portuguese, keeping Dart API names
  and code comments in their original form.
- Use short pages organized around one task or concept.
- Prefer the custom MDX components already available in `components/` for tabs,
  accordions, code blocks, file trees, and inline tables of contents.
- Link to the package README or pub.dev only for API details that should not be
  duplicated in the guide.
