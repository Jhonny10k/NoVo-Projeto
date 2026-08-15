import { SiteRenderer, type SiteRenderData, type SiteSectionData } from "@/components/site/site-renderer";
import { requireUser } from "@/lib/auth/require-user";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { requireFeature } from "@/lib/plans/entitlements";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function SitePreviewPage() {
  await requireUser();
  await requireFeature("site");
  const organization = await requireCurrentOrganization();
  const supabase = await createClient();
  const [{ data: orgDetails }, { data: site }, { data: sections }, { data: products }, { data: services }] = await Promise.all([
    supabase.from("organizations").select("name,slug,segment,whatsapp,phone,city,state").eq("id",organization.id).single(),
    supabase.from("site_configs").select("headline,subheadline,about,primary_color,cover_image_url").eq("organization_id",organization.id).single(),
    supabase.from("site_sections").select("id,section_type,enabled,sort_order,content").eq("organization_id",organization.id).order("sort_order"),
    supabase.from("products").select("id,name,description,price_cents,promotional_price_cents,image_url").eq("organization_id",organization.id).eq("available",true).order("featured",{ascending:false}),
    supabase.from("services").select("id,name,description,starting_price_cents,image_url").eq("organization_id",organization.id).eq("active",true).order("created_at",{ascending:false})
  ]);
  const normalizedSections: SiteSectionData[] = (sections ?? []).map((section) => ({ id: section.id, type: section.section_type, enabled: section.enabled, sort_order: section.sort_order, content: (section.content ?? {}) as Record<string,unknown> }));
  const content: SiteRenderData = { organization: orgDetails ?? { name: organization.name, slug: organization.slug, segment: null, whatsapp: null, phone: null, city: null, state: null }, site, sections: normalizedSections, products: products ?? [], services: services ?? [] };
  return <SiteRenderer content={content} preview />;
}
