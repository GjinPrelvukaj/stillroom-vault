// The one way the licence signer sends mail. The provider isn't chosen yet: set EMAIL_PROVIDER to one of the cases
// below (and EMAIL_API_KEY, EMAIL_FROM), or add a case. Nothing else in the signer knows which one it is.

export interface Email {
  to: string;
  subject: string;
  text: string;
  /** Sent beside the text, for mail apps that show it. */
  html?: string;
  /** Where a reply goes: the sending address only sends. */
  replyTo?: string;
}

export interface EmailEnv {
  EMAIL_PROVIDER?: string;
  EMAIL_API_KEY?: string;
  /** "Stillroom Vault <licences@stillroomvault.com>", on a domain the provider has verified. */
  EMAIL_FROM?: string;
}

export async function sendEmail(env: EmailEnv, mail: Email, fetcher: typeof fetch = fetch): Promise<void> {
  const { EMAIL_PROVIDER: provider, EMAIL_API_KEY: key, EMAIL_FROM: from } = env;
  if (!key || !from) throw new Error('email is not set up (EMAIL_API_KEY, EMAIL_FROM)');
  let response: Response;
  switch (provider) {
    case 'resend':
      response = await fetcher('https://api.resend.com/emails', {
        method: 'POST',
        headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ from, to: [mail.to], subject: mail.subject, text: mail.text, html: mail.html, reply_to: mail.replyTo }),
      });
      break;
    case 'postmark':
      response = await fetcher('https://api.postmarkapp.com/email', {
        method: 'POST',
        headers: { 'X-Postmark-Server-Token': key, 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({ From: from, To: mail.to, Subject: mail.subject, TextBody: mail.text, HtmlBody: mail.html, ReplyTo: mail.replyTo, MessageStream: 'outbound' }),
      });
      break;
    default:
      throw new Error(`unknown EMAIL_PROVIDER "${provider ?? ''}"`);
  }
  // The status only: a provider's error body can echo the address.
  if (!response.ok) throw new Error(`email provider answered ${response.status}`);
}
