// The MIT licence that covers tools/, served as it is in the repository.
import type { APIRoute } from 'astro';
import { repoFile } from '../../lib/repo';

export const GET: APIRoute = () =>
  new Response(repoFile('tools/LICENSE.md'), { headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
