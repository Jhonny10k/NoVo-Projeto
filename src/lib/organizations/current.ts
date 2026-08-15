import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export type CurrentOrganization = {
  id: string;
  name: string;
  slug: string;
  role: string;
};

export async function getCurrentOrganization(): Promise<CurrentOrganization | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("organization_members")
    .select("role, organizations!inner(id,name,slug)")
    .eq("status", "active")
    .order("created_at", { ascending: true })
    .limit(1)
    .maybeSingle();

  if (error || !data) return null;
  const organization = Array.isArray(data.organizations) ? data.organizations[0] : data.organizations;
  if (!organization) return null;
  return { id: organization.id, name: organization.name, slug: organization.slug, role: data.role };
}

export async function requireCurrentOrganization(): Promise<CurrentOrganization> {
  const organization = await getCurrentOrganization();
  if (!organization) {
    redirect("/onboarding");
    throw new Error("Redirecionamento de onboarding não executado.");
  }
  return organization;
}
