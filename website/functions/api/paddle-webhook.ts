// stillroomvault.com/api/paddle-webhook: Paddle's webhook, which signs and emails a licence. The work is in
// server/webhook.ts; see website/README.md ("The licence signer") for its secrets and bindings.

import { handleWebhook, type Env } from '../../server/webhook.ts';

export const onRequest = (context: { request: Request; env: Env }) => handleWebhook(context.request, context.env);
