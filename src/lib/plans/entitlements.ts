import { redirect } from "next/navigation";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { createClient } from "@/lib/supabase/server";

export const featureCodes = [
  "site", "catalog", "leads", "dashboard", "forms", "basic_seo",
  "crm", "quotes", "tasks", "exports", "appointments", "automations", "analytics", "advanced_site",
  "ai_assistant", "ai_responses", "ai_copy", "ai_quotes", "ai_insights", "email_transactional", "whatsapp_official", "google_calendar", "google_maps",
  "public_api", "outbound_webhooks", "white_label", "multi_unit"
] as const;

export type FeatureCode = (typeof featureCodes)[number];

export const featureLabels: Record<FeatureCode, string> = {
  site: "Site profissional",
  catalog: "Catálogo",
  leads: "Leads",
  dashboard: "Dashboard",
  forms: "Formulários públicos",
  basic_seo: "SEO básico",
  crm: "CRM e clientes",
  quotes: "Orçamentos",
  tasks: "Tarefas",
  exports: "Exportações CSV",
  appointments: "Agendamentos",
  automations: "Automações comerciais",
  analytics: "Analytics",
  advanced_site: "Personalização avançada do site",
  ai_assistant: "Assistente IA",
  ai_responses: "Sugestão de respostas com IA",
  ai_copy: "Textos com IA",
  ai_quotes: "Apoio a orçamentos com IA",
  ai_insights: "Insights com IA",
  email_transactional: "E-mail transacional",
  whatsapp_official: "WhatsApp oficial",
  google_calendar: "Google Calendar",
  google_maps: "Google Maps",
  public_api: "API pública",
  outbound_webhooks: "Webhooks para clientes",
  white_label: "White-label e domínio personalizado",
  multi_unit: "Múltiplas unidades"
};

export async function hasFeature(feature: FeatureCode) {
  const organization = await requireCurrentOrganization();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("has_feature", {
    p_organization_id: organization.id,
    p_feature: feature
  });
  return !error && data === true;
}

export async function requireFeature(feature: FeatureCode) {
  const allowed = await hasFeature(feature);
  if (!allowed) redirect(`/assinatura?recurso=${encodeURIComponent(feature)}`);
}

export async function getFeatureLimit(limit: string) {
  const organization = await requireCurrentOrganization();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("feature_limit", {
    p_organization_id: organization.id,
    p_limit: limit
  });
  if (error || typeof data !== "number") return null;
  return data;
}
