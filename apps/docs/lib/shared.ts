export const appName = 'better_effect';
export const appDescription =
  'Arquitetura tipada para aplicações Dart e Flutter com Effects, dependências explícitas, lifetimes e diagnósticos.';
export const appKeywords = [
  'Dart',
  'Flutter',
  'result_dart',
  'better_effect',
  'better_effect_flutter',
  'dependency injection',
  'typed errors',
  'typed effects',
  'MVVM',
  'resource management',
  'runtime',
  'pub.dev',
];
const configuredSiteUrl =
  process.env.NEXT_PUBLIC_SITE_URL ??
  (process.env.VERCEL_URL ? `https://${process.env.VERCEL_URL}` : 'http://localhost:3000');
export const siteUrl = new URL(configuredSiteUrl);
export const socialImagePath = '/opengraph-image';
export const docsRoute = '/docs';
export const docsImageRoute = '/og/docs';
export const docsContentRoute = '/llms.mdx/docs';

export const gitConfig = {
  user: 'nitoba',
  repo: 'better-effect-dart',
  branch: 'main',
};
