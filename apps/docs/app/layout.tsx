import { RootProvider } from 'fumadocs-ui/provider/next';
import './global.css';
import { Inter } from 'next/font/google';
import type { Metadata } from 'next';
import { appDescription, appKeywords, appName, siteUrl, socialImagePath } from '@/lib/shared';

const inter = Inter({
  subsets: ['latin'],
});

export const metadata: Metadata = {
  metadataBase: siteUrl,
  title: {
    default: `${appName} — typed application architecture`,
    template: `%s | ${appName}`,
  },
  description: appDescription,
  applicationName: appName,
  keywords: appKeywords,
  authors: [{ name: 'Nitoba', url: 'https://github.com/nitoba' }],
  creator: 'Nitoba',
  publisher: 'Nitoba',
  category: 'technology',
  alternates: { canonical: '/' },
  openGraph: {
    type: 'website',
    url: '/',
    siteName: appName,
    locale: 'pt_BR',
    title: `${appName} — typed application architecture`,
    description: appDescription,
    images: [{ url: socialImagePath, width: 1200, height: 630, alt: appName }],
  },
  twitter: {
    card: 'summary_large_image',
    title: `${appName} — typed application architecture`,
    description: appDescription,
    images: [socialImagePath],
  },
};

export default function Layout({ children }: LayoutProps<'/'>) {
  return (
    <html lang="pt-BR" className={inter.className} suppressHydrationWarning>
      <body className="flex flex-col min-h-screen">
        <RootProvider theme={{ defaultTheme: 'system', enableSystem: true }}>
          {children}
        </RootProvider>
      </body>
    </html>
  );
}
