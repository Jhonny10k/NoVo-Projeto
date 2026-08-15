"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { requireFeature } from "@/lib/plans/entitlements";
import { createClient } from "@/lib/supabase/server";
import { uploadOrganizationImage } from "@/lib/storage/images";

function field(formData: FormData, key: string, maxLength: number) {
  const raw = formData.get(key);
  if (typeof raw !== "string") return "";
  return raw.trim().slice(0, maxLength);
}

function enabled(formData: FormData) {
  return formData.get("enabled") === "on";
}

async function context() {
  await requireFeature("site");
  const organization = await requireCurrentOrganization();
  return { organization, supabase: await createClient() };
}

export async function saveSiteSettingsAction(formData: FormData) {
  await requireFeature("advanced_site");
  const { organization, supabase } = await context();
  const primaryColorRaw = field(formData, "primary_color", 20);
  const primaryColor = /^#[0-9a-f]{6}$/i.test(primaryColorRaw) ? primaryColorRaw : null;
  const payload: Record<string, unknown> = { primary_color: primaryColor };
  const cover = formData.get("cover_image");
  if (cover instanceof File && cover.size > 0) {
    try {
      const image = await uploadOrganizationImage({ organizationId: organization.id, folder: "site", file: cover });
      payload.cover_image_url = image.publicUrl;
    } catch {
      redirect("/site?erro=imagem");
    }
  }
  const { error } = await supabase.from("site_configs").update(payload).eq("organization_id", organization.id);
  if (error) redirect("/site?erro=salvar");
  revalidatePath("/site");
  revalidatePath("/site/preview");
  redirect("/site?status=configuracao-salva");
}

function sectionContent(type: string, formData: FormData) {
  if (type === "hero") return {
    title: field(formData, "title", 180),
    subtitle: field(formData, "subtitle", 320),
    cta_label: field(formData, "cta_label", 80) || "Solicitar orçamento",
    cta_target: ["quote", "whatsapp", "contact", "booking"].includes(field(formData, "cta_target", 20)) ? field(formData, "cta_target", 20) : "quote"
  };
  if (type === "about") return { title: field(formData, "title", 100) || "Sobre", text: field(formData, "text", 3000) };
  if (type === "services" || type === "products") return { title: field(formData, "title", 100) || (type === "services" ? "Serviços" : "Produtos") };
  if (type === "contact") return { title: field(formData, "title", 100) || "Contato", text: field(formData, "text", 600) };
  if (type === "cta") return {
    title: field(formData, "title", 180), text: field(formData, "text", 600), label: field(formData, "label", 80) || "Solicitar orçamento",
    target: ["quote", "whatsapp", "contact", "booking"].includes(field(formData, "target", 20)) ? field(formData, "target", 20) : "quote"
  };
  return {};
}

export async function saveSiteSectionAction(formData: FormData) {
  const { organization, supabase } = await context();
  const id = field(formData, "section_id", 80);
  if (!id) redirect("/site?erro=bloco");
  const { data: section } = await supabase.from("site_sections").select("id,section_type").eq("organization_id", organization.id).eq("id", id).maybeSingle();
  if (!section) redirect("/site?erro=bloco");
  const content = sectionContent(section.section_type, formData);
  const { error } = await supabase.from("site_sections").update({ enabled: enabled(formData), content }).eq("organization_id", organization.id).eq("id", id);
  if (error) redirect("/site?erro=salvar");

  if (section.section_type === "hero") {
    const hero = content as { title?: string; subtitle?: string };
    await supabase.from("site_configs").update({ headline: hero.title || organization.name, subheadline: hero.subtitle || null }).eq("organization_id", organization.id);
  } else if (section.section_type === "about") {
    const about = content as { text?: string };
    await supabase.from("site_configs").update({ about: about.text || null }).eq("organization_id", organization.id);
  }
  revalidatePath("/site");
  revalidatePath("/site/preview");
  redirect("/site?status=bloco-salvo");
}

export async function moveSiteSectionAction(formData: FormData) {
  const { organization, supabase } = await context();
  const sectionId = field(formData, "section_id", 80);
  const direction = field(formData, "direction", 10);
  if (!sectionId || !["up", "down"].includes(direction)) redirect("/site?erro=bloco");
  const { data: section } = await supabase.from("site_sections").select("id").eq("organization_id", organization.id).eq("id", sectionId).maybeSingle();
  if (!section) redirect("/site?erro=bloco");
  const { error } = await supabase.rpc("move_site_section", { p_section_id: sectionId, p_direction: direction });
  if (error) redirect("/site?erro=ordem");
  revalidatePath("/site");
  revalidatePath("/site/preview");
  redirect("/site?status=ordem-salva");
}

export async function saveSiteDraftAction() {
  await requireFeature("site");
  redirect("/site?status=rascunho-salvo");
}

export async function publishSiteAction() {
  const { organization, supabase } = await context();
  const { error } = await supabase.rpc("publish_site_snapshot", { p_organization_id: organization.id });
  if (error) redirect("/site?erro=publicar");
  revalidatePath("/site");
  revalidatePath(`/empresa/${organization.slug}`);
  redirect("/site?status=publicado");
}

export async function applySiteTemplateAction(formData: FormData) {
  const { organization, supabase } = await context();
  if (!["owner", "admin"].includes(organization.role)) redirect("/site?erro=permissao");
  const key = field(formData, "template", 40);
  const { getSiteTemplate } = await import("@/lib/site/templates");
  const template = getSiteTemplate(key);
  if (!template) { redirect("/site?erro=template"); throw new Error("redirect"); }
  const { error } = await supabase.rpc("apply_site_template", {
    p_organization_id: organization.id,
    p_template_key: template.key,
    p_template: template.payload
  });
  if (error) redirect("/site?erro=template");
  revalidatePath("/site");
  revalidatePath("/site/preview");
  redirect("/site?status=template-aplicado");
}
