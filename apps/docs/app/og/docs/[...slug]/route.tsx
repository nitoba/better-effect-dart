import { getPageImageUrl, source } from '@/lib/source';
import { notFound } from 'next/navigation';
import { ImageResponse } from 'next/og';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { appName } from '@/lib/shared';

export const revalidate = false;

export async function GET(_req: Request, { params }: RouteContext<'/og/docs/[...slug]'>) {
  const { slug } = await params;
  const page = source.getPage(slug.slice(0, -1));
  if (!page) notFound();

  const logo = await readFile(join(process.cwd(), 'public', 'logo.png'));
  const logoData = `data:image/png;base64,${logo.toString('base64')}`;

  return new ImageResponse(
    <div
      style={{
        width: '100%',
        height: '100%',
        display: 'flex',
        flexDirection: 'column',
        justifyContent: 'space-between',
        padding: '64px 72px',
        color: '#f4f4f1',
        background: '#050505',
        border: '1px solid #242424',
        fontFamily: 'sans-serif',
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 18 }}>
        <div
          style={{
            width: 76,
            height: 76,
            backgroundImage: `url(${logoData})`,
            backgroundPosition: 'center',
            backgroundRepeat: 'no-repeat',
            backgroundSize: 'contain',
          }}
        />
        <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
          <div style={{ fontSize: 30, fontWeight: 600, letterSpacing: '-0.03em' }}>{appName}</div>
          <div style={{ fontSize: 18, color: '#969693' }}>Dart + Flutter</div>
        </div>
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 18, maxWidth: 1040 }}>
        <div style={{ fontSize: 48, lineHeight: 1.1, fontWeight: 600, letterSpacing: '-0.035em' }}>
          {page.data.title}
        </div>
        <div style={{ fontSize: 24, lineHeight: 1.35, color: '#969693' }}>
          {page.data.description}
        </div>
      </div>
    </div>,
    {
      width: 1200,
      height: 630,
    },
  );
}

export function generateStaticParams() {
  return source.getPages().map((page) => ({
    lang: page.locale,
    slug: getPageImageUrl(page).segments,
  }));
}
