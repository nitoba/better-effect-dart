import { brandLogoPngResponse } from '@/lib/brand/response';

export const dynamic = 'force-static';

export function GET() {
  return brandLogoPngResponse();
}
