import "server-only";

export type BillingProviderName = "disabled" | "mercadopago";

export type BillingAvailability = {
  provider: BillingProviderName;
  configured: boolean;
  message: string;
};

export function getBillingAvailability(): BillingAvailability {
  const configuredProvider = process.env.BILLING_PROVIDER ?? "disabled";
  if (configuredProvider === "mercadopago") {
    const configured = Boolean(process.env.MERCADO_PAGO_ACCESS_TOKEN && process.env.MERCADO_PAGO_WEBHOOK_SECRET);
    return {
      provider: "mercadopago",
      configured,
      message: configured
        ? "Mercado Pago configurado. A assinatura só é ativada após confirmação real do provider."
        : "Mercado Pago selecionado, mas faltam credenciais do servidor ou a assinatura secreta do Webhook."
    };
  }

  return {
    provider: "disabled",
    configured: false,
    message: "Pagamentos ainda não estão configurados. Nenhuma cobrança será simulada ou marcada como paga."
  };
}
