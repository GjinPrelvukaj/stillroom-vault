// /releases.json: every released version, newest first, for the changelog's "you have 1.0.0, 1.0.1 is out" note. The
// app's Check for Updates opens /changelog/?v=<its version>; the page fetches this from this site only.
import type { APIRoute } from 'astro';
import { releases } from '../lib/releases';

export const GET: APIRoute = () =>
  Response.json(releases().map(({ version, date, security, slug }) => ({ version, date, security, slug })));
