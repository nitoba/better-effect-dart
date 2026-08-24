import type { MetadataRoute } from 'next';
import { appDescription, appName, siteUrl } from '@/lib/shared';

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: appName,
    short_name: appName,
    description: appDescription,
    start_url: '/',
    scope: '/',
    display: 'standalone',
    background_color: '#050505',
    theme_color: '#050505',
    lang: 'pt-BR',
    icons: [
      {
        src: new URL('/icon.png', siteUrl).toString(),
        sizes: '192x192',
        type: 'image/png',
        purpose: 'any',
      },
    ],
  };
}
