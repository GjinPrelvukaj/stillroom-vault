// stillroomvault.com/download/<zip>: serves the file as before, then counts the download (server/downloads.ts) if the
// file was there, so made-up names never make a key. A counting failure never stops the download.
// ponytail: KV's free tier takes 1,000 writes a day; past that, counts are lost but downloads still work.
import { count, countKey, type DownloadsEnv } from '../../server/downloads.ts';

export const onRequest = async (context: {
  request: Request;
  env: DownloadsEnv;
  next: () => Promise<Response>;
  waitUntil: (promise: Promise<unknown>) => void;
}) => {
  const response = await context.next();
  if (response.status === 200 || response.status === 206) {
    context.waitUntil(count(context.env.DOWNLOADS, countKey(context.request)).catch(() => {}));
  }
  return response;
};
