import { brandLogoBase64 } from './logo';

export function brandLogoPngResponse() {
  const buffer = Buffer.from(brandLogoBase64, 'base64');
  const bytes = Uint8Array.from(buffer);

  return new Response(bytes, {
    headers: {
      'Content-Type': 'image/png',
      'Cache-Control': 'public, max-age=31536000, immutable',
    },
  });
}
