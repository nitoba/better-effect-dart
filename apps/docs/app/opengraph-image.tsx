import { ImageResponse } from 'next/og';
import { appDescription, appName } from '@/lib/shared';
import { brandLogoDataUri } from '@/lib/brand/logo';

export const alt = `${appName} — arquitetura tipada para Dart e Flutter`;
export const size = { width: 1200, height: 630 };
export const contentType = 'image/png';

export default function OpenGraphImage() {
  return new ImageResponse(
    <div
      style={{
        width: '100%',
        height: '100%',
        display: 'flex',
        flexDirection: 'column',
        justifyContent: 'space-between',
        padding: '70px 78px',
        color: '#f4f4f1',
        background: '#050505',
        border: '1px solid #242424',
        fontFamily: 'sans-serif',
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 24 }}>
        <div
          style={{
            width: 112,
            height: 112,
            backgroundImage: `url(${brandLogoDataUri})`,
            backgroundPosition: 'center',
            backgroundRepeat: 'no-repeat',
            backgroundSize: 'contain',
          }}
        />
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          <div style={{ fontSize: 52, fontWeight: 600, letterSpacing: '-0.04em' }}>{appName}</div>
          <div style={{ fontSize: 20, color: '#969693' }}>Dart + Flutter</div>
        </div>
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 18, maxWidth: 980 }}>
        <div style={{ fontSize: 42, lineHeight: 1.12, color: '#f4f4f1' }}>
          Effects, Services, Lifetimes.
        </div>
        <div style={{ fontSize: 24, lineHeight: 1.35, color: '#969693' }}>{appDescription}</div>
      </div>
    </div>,
    size,
  );
}
