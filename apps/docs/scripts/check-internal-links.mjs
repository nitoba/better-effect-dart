import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';

const docsDir = path.resolve('content/docs');
const siteOrigin = 'https://better-effect.invalid';

async function walk(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = [];

  for (const entry of entries) {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      files.push(...(await walk(absolute)));
    } else if (entry.isFile() && entry.name.endsWith('.mdx')) {
      files.push(absolute);
    }
  }

  return files;
}

function routeFor(file) {
  const relative = path.relative(docsDir, file).split(path.sep).join('/');
  const withoutExtension = relative.replace(/\.mdx$/, '');

  if (withoutExtension === 'index') return '/docs';
  if (withoutExtension.endsWith('/index')) {
    return `/docs/${withoutExtension.slice(0, -'/index'.length)}`;
  }

  return `/docs/${withoutExtension}`;
}

function stripFencedCode(source) {
  return source.replace(/```[\s\S]*?```/g, '');
}

function lineNumberAt(source, index) {
  return source.slice(0, index).split('\n').length;
}

function collectLinks(source) {
  const links = [];
  const markdown = /(?<!!)\[[^\]]*\]\(([^)\s]+)(?:\s+["'][^"']*["'])?\)/g;
  const href = /\bhref\s*=\s*(?:["']([^"']+)["']|\{\s*["']([^"']+)["']\s*\})/g;

  for (const match of source.matchAll(markdown)) {
    links.push({ href: match[1], index: match.index ?? 0 });
  }

  for (const match of source.matchAll(href)) {
    links.push({ href: match[1] ?? match[2], index: match.index ?? 0 });
  }

  return links;
}

function isExternalOrNonPageLink(href) {
  if (!href || href.startsWith('#')) return true;
  if (/^[a-z][a-z0-9+.-]*:/i.test(href)) return true;
  if (href.startsWith('//')) return true;
  return false;
}

function normalizedPathname(href, currentRoute) {
  const url = new URL(href, `${siteOrigin}${currentRoute}`);
  return url.pathname.length > 1 ? url.pathname.replace(/\/$/, '') : url.pathname;
}

function shouldValidateAsDocumentationRoute(pathname) {
  if (pathname === '/docs' || pathname.startsWith('/docs/')) return true;

  return /^\/(getting-started|guides|packages|ai|maintainers)(\/|$)/.test(pathname) ||
    pathname === '/semantics';
}

const files = await walk(docsDir);
const routes = new Set(files.map(routeFor));
const failures = [];
let checked = 0;

for (const file of files) {
  const original = await readFile(file, 'utf8');
  const source = stripFencedCode(original);
  const currentRoute = routeFor(file);

  for (const link of collectLinks(source)) {
    if (isExternalOrNonPageLink(link.href)) continue;

    const pathname = normalizedPathname(link.href, currentRoute);
    if (!shouldValidateAsDocumentationRoute(pathname)) continue;

    checked += 1;
    if (!routes.has(pathname)) {
      const relativeFile = path.relative(process.cwd(), file).split(path.sep).join('/');
      failures.push(
        `${relativeFile}:${lineNumberAt(source, link.index)} -> ${link.href} resolves to ${pathname}, but that documentation route does not exist.`,
      );
    }
  }
}

if (failures.length > 0) {
  console.error(`Found ${failures.length} broken internal documentation link(s):\n`);
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log(`Internal documentation links OK (${routes.size} routes, ${checked} internal links checked).`);
