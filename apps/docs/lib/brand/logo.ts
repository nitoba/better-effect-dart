import { brandLogoChunk0 } from './logo/chunk0';
import { brandLogoChunk1 } from './logo/chunk1';
import { brandLogoChunk2 } from './logo/chunk2';
import { brandLogoChunk3 } from './logo/chunk3';
import { brandLogoChunk4 } from './logo/chunk4';

export const brandLogoBase64 = [
  brandLogoChunk0,
  brandLogoChunk1,
  brandLogoChunk2,
  brandLogoChunk3,
  brandLogoChunk4,
].join('');

export const brandLogoDataUri = `data:image/png;base64,${brandLogoBase64}`;
export const brandLogoSize = 192;
