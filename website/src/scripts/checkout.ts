// The checkout page: loads Paddle.js, opens Paddle's form inline, fills the order summary from the totals Paddle
// sends (shown as Paddle gives them, never worked out here), switches edition without a reload, and says thank you.
// A Paddle payment link (?_ptxn=…, from Paddle's emails) opens its own transaction here too: Paddle.js does that itself.
interface CheckoutEvent {
  name?: string;
  data?: {
    currency_code: string;
    customer?: { email?: string };
    items: { price_id: string }[];
    totals: { subtotal: number; tax: number; total: number };
  };
}
interface PaddleGlobal {
  Environment: { set(env: string): void };
  Initialize(options: object): void;
  Checkout: { open(options: object): void; updateItems(items: object[]): void };
}

const root = document.querySelector<HTMLElement>('[data-checkout]');
const $ = <T extends HTMLElement = HTMLElement>(s: string) => document.querySelector<T>(s);

if (root) {
  const plans = [...root.querySelectorAll<HTMLAnchorElement>('[data-plan]')];
  const status = $('[data-status]')!;
  const asked = new URLSearchParams(location.search).get('plan');
  let current = plans.find((p) => p.dataset.plan === asked) ?? plans[0]!;

  const show = (plan: HTMLAnchorElement) => {
    current = plan;
    plans.forEach((p) => p.setAttribute('aria-current', String(p === plan)));
    $('[data-show-name]')!.textContent = plan.dataset.name ?? '';
    $('[data-show-who]')!.textContent = plan.dataset.who ?? '';
    for (const k of ['subtotal', 'tax']) $(`[data-${k}]`)!.textContent = '…';
    $('[data-total]')!.textContent = plan.dataset.from ?? '';
  };
  show(current);

  const summarise = (data: NonNullable<CheckoutEvent['data']>) => {
    const plan = plans.find((p) => p.dataset.price === data.items[0]?.price_id);
    if (plan && plan !== current) show(plan);
    const money = new Intl.NumberFormat('en', { style: 'currency', currency: data.currency_code });
    $('[data-subtotal]')!.textContent = money.format(data.totals.subtotal);
    $('[data-tax]')!.textContent = money.format(data.totals.tax);
    $('[data-total]')!.textContent = money.format(data.totals.total);
  };

  const thank = (data: CheckoutEvent['data']) => {
    const done = $('[data-done]')!;
    if (data?.customer?.email) $('[data-email]')!.textContent = data.customer.email;
    root.hidden = true;
    done.hidden = false;
    done.focus();
    done.scrollIntoView({ block: 'center' });
  };

  const script = document.createElement('script');
  script.src = 'https://cdn.paddle.com/paddle/v2/paddle.js';
  script.async = true;
  script.addEventListener('error', () => {
    status.textContent = 'The checkout couldn’t load. A blocker may be stopping cdn.paddle.com; allow it for this page, or try again.';
  });
  script.addEventListener('load', () => {
    const paddle = (window as unknown as { Paddle?: PaddleGlobal }).Paddle;
    if (!paddle) return;
    if (root.dataset.env === 'sandbox') paddle.Environment.set('sandbox');
    paddle.Initialize({
      token: root.dataset.token,
      checkout: {
        settings: {
          displayMode: 'inline',
          frameTarget: 'checkout-frame',
          frameInitialHeight: 450,
          frameStyle: 'width: 100%; min-width: 280px; background-color: transparent; border: none;',
          variant: 'one-page',
          theme: 'light',
          locale: 'en',
        },
      },
      eventCallback: (event: CheckoutEvent) => {
        if (event.name === 'checkout.loaded') status.textContent = '';
        if (event.name === 'checkout.completed') thank(event.data);
        else if (event.data?.totals) summarise(event.data);
      },
    });
    if (!new URLSearchParams(location.search).has('_ptxn')) {
      paddle.Checkout.open({ items: [{ priceId: current.dataset.price, quantity: 1 }] });
    }
    plans.forEach((p) =>
      p.addEventListener('click', (e) => {
        e.preventDefault();
        if (p === current) return;
        show(p);
        history.replaceState(null, '', p.href);
        paddle.Checkout.updateItems([{ priceId: p.dataset.price, quantity: 1 }]);
      }),
    );
  });
  document.head.append(script);
}
