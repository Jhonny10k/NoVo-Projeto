import { InvalidWebhookSignatureError, WebhookSignatureValidator } from "mercadopago";
import { getMercadoPagoPreapproval } from "@/lib/billing/mercadopago";
import { syncMercadoPagoPreapproval } from "@/lib/billing/sync";
import { createAdminClient } from "@/lib/supabase/admin";

export const runtime = "nodejs";

type WebhookBody = {
  id?: string | number;
  type?: string;
  action?: string;
  data?: { id?: string | number };
};

export async function POST(request: Request) {
  const secret = process.env.MERCADO_PAGO_WEBHOOK_SECRET;
  if (!secret) return Response.json({ error: "webhook not configured" }, { status: 503 });

  const url = new URL(request.url);
  const body = await request.json().catch(() => null) as WebhookBody | null;
  if (!body) return Response.json({ error: "invalid payload" }, { status: 400 });

  const dataId = url.searchParams.get("data.id") ?? (body.data?.id == null ? null : String(body.data.id));
  const xSignature = request.headers.get("x-signature");
  const xRequestId = request.headers.get("x-request-id");
  if (!dataId || !xSignature || !xRequestId) return Response.json({ error: "missing signature data" }, { status: 401 });

  try {
    WebhookSignatureValidator.validate({ xSignature, xRequestId, dataId, secret });
  } catch (error) {
    if (error instanceof InvalidWebhookSignatureError) {
      return Response.json({ error: "invalid signature" }, { status: 401 });
    }
    return Response.json({ error: "signature validation failed" }, { status: 500 });
  }

  const admin = createAdminClient();
  const providerEventId = body.id == null ? xRequestId : String(body.id);
  const topic = body.type ?? url.searchParams.get("type") ?? "unknown";
  const { data: event, error: eventError } = await admin.from("billing_webhook_events").insert({
    provider: "mercadopago",
    provider_event_id: providerEventId,
    topic,
    action: body.action ?? null,
    resource_id: dataId,
    payload: body
  }).select("id").single();

  if (eventError?.code === "23505") return Response.json({ ok: true, duplicate: true });
  if (eventError || !event) return Response.json({ error: "event persistence failed" }, { status: 500 });

  try {
    if (["subscription_preapproval", "subscription"].includes(topic)) {
      const resource = await getMercadoPagoPreapproval(dataId);
      const result = await syncMercadoPagoPreapproval(admin, resource);
      await admin.from("billing_webhook_events").update({
        organization_id: result.organizationId,
        processed_at: new Date().toISOString()
      }).eq("id", event.id);
    } else {
      await admin.from("billing_webhook_events").update({ processed_at: new Date().toISOString() }).eq("id", event.id);
    }
    return Response.json({ ok: true });
  } catch (error) {
    await admin.from("billing_webhook_events").update({
      error_message: error instanceof Error ? error.message.slice(0, 500) : "Falha desconhecida"
    }).eq("id", event.id);
    return Response.json({ error: "processing failed" }, { status: 500 });
  }
}
