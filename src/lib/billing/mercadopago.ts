import "server-only";

const API_BASE = "https://api.mercadopago.com";

export type MercadoPagoPreapproval = {
  id: string;
  status: string;
  external_reference?: string | null;
  init_point?: string | null;
  payer_id?: string | number | null;
  payer_email?: string | null;
  next_payment_date?: string | null;
  auto_recurring?: {
    transaction_amount?: number | string | null;
    currency_id?: string | null;
  } | null;
};

function accessToken() {
  const token = process.env.MERCADO_PAGO_ACCESS_TOKEN;
  if (!token) throw new Error("MERCADO_PAGO_ACCESS_TOKEN não configurado.");
  return token;
}

async function apiRequest<T>(path: string, init: RequestInit): Promise<T> {
  const response = await fetch(`${API_BASE}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${accessToken()}`,
      "Content-Type": "application/json",
      ...(init.headers ?? {})
    },
    signal: AbortSignal.timeout(12_000),
    cache: "no-store"
  });

  const body = await response.json().catch(() => null);
  if (!response.ok) {
    const message = body && typeof body === "object" && "message" in body ? String(body.message) : `HTTP ${response.status}`;
    throw new Error(`Mercado Pago: ${message}`);
  }
  return body as T;
}

function assertCheckoutUrl(value: string | null | undefined) {
  if (!value) throw new Error("Mercado Pago não retornou o link de checkout.");
  const url = new URL(value);
  const hostname = url.hostname.toLowerCase();
  if (url.protocol !== "https:" || !(hostname === "mercadopago.com" || hostname.endsWith(".mercadopago.com") || hostname.endsWith(".mercadopago.com.br"))) {
    throw new Error("Link de checkout inesperado retornado pelo provider.");
  }
  return url.toString();
}

export async function createMercadoPagoSubscription(input: {
  sessionId: string;
  payerEmail: string;
  reason: string;
  amountCents: number;
  billingCycle: "monthly" | "annual";
  backUrl: string;
}) {
  const body = {
    reason: input.reason.slice(0, 120),
    external_reference: input.sessionId,
    payer_email: input.payerEmail,
    auto_recurring: {
      frequency: input.billingCycle === "annual" ? 12 : 1,
      frequency_type: "months",
      transaction_amount: input.amountCents / 100,
      currency_id: "BRL"
    },
    back_url: input.backUrl,
    status: "pending"
  };

  const resource = await apiRequest<MercadoPagoPreapproval>("/preapproval", {
    method: "POST",
    body: JSON.stringify(body)
  });

  return { resource, checkoutUrl: assertCheckoutUrl(resource.init_point) };
}

export async function getMercadoPagoPreapproval(id: string) {
  return apiRequest<MercadoPagoPreapproval>(`/preapproval/${encodeURIComponent(id)}`, { method: "GET" });
}

export async function cancelMercadoPagoPreapproval(id: string) {
  return apiRequest<MercadoPagoPreapproval>(`/preapproval/${encodeURIComponent(id)}`, {
    method: "PUT",
    body: JSON.stringify({ status: "canceled" })
  });
}
