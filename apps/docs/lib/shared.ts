export const appName = 'better_effect';
export const appDescription =
  'Arquitetura tipada para aplicações Dart e Flutter com Effects, dependências explícitas, lifetimes e diagnósticos.';
export const appKeywords = [
  'Dart',
  'Flutter',
  'dependency injection',
  'MVVM',
  'typed effects',
  'pub.dev',
];
const configuredSiteUrl =
  process.env.NEXT_PUBLIC_SITE_URL ??
  (process.env.VERCEL_URL ? `https://${process.env.VERCEL_URL}` : 'http://localhost:3000');
export const siteUrl = new URL(configuredSiteUrl);
export const socialImagePath = '/og/docs/image.png';
export const docsRoute = '/docs';
export const docsImageRoute = '/og/docs';
export const docsContentRoute = '/llms.mdx/docs';

// fill this with your actual GitHub info, for example:
export const gitConfig = {
  user: 'nitoba',
  repo: 'better-effect-dart',
  branch: 'main',
};
