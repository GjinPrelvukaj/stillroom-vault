// The vault reader, served from this site exactly as it is in the repository (tools/, MIT).
import type { APIRoute } from 'astro';
import { repoFile } from '../../lib/repo';

export const GET: APIRoute = () =>
  new Response(repoFile('tools/stillroom-open.py'), { headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
