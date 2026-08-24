import { ImageResponse } from 'next/og';
import { brandLogoDataUri } from '@/lib/brand/logo';

export const dynamic = 'force-static';

export function GET() {
  return new ImageResponse(
    <div
      style={{
        width: '180px',
        height: '180px',
        display: 'flex',
        backgroundColor: '#050505',
        backgroundImage: `url(${brandLogoDataUri})`,
        backgroundPosition: 'center',
        backgroundRepeat: 'no-repeat',
        backgroundSize: '86%',
      }}
    />,
    { width: 180, height: 180 },
  );
}
