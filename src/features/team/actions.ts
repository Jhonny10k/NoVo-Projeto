"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireUser } from "@/lib/auth/require-user";
import { getPublicAppUrl } from "@/lib/env";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

const ALLOWED_ROLES = new Set(["admin", "sales", "support", "viewer"]);

function text(formData: FormData, key: string, max = 320) {
  const value = formData.get(key);
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

async function requireTeamAdmin() {
  const [user, organization] = await Promise.all([requireUser(), requireCurrentOrganization()]);
  if (!["owner", "admin"].includes(organization.role)) redirect("/dashboard");
  return { user, organization };
}

async function getUserSeatLimit(organizationId: string) {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("feature_limit", { p_organization_id: organizationId, p_limit: "users" });
  if (!error && Number.isInteger(data) && Number(data) > 0) return Number(data);
  return 1;
}

export async function inviteMemberAction(formData: FormData) {
  const { user, organization } = await requireTeamAdmin();
  const email = text(formData, "email", 320).toLowerCase();
  const role = text(formData, "role", 30);
  if (!email.includes("@") || !ALLOWED_ROLES.has(role)) redirect("/equipe?erro=campos");

  const supabase = await createClient();
  const { count } = await supabase
    .from("organization_members")
    .select("id", { count: "exact", head: true })
    .eq("organization_id", organization.id)
    .in("status", ["active", "invited"]);
  const limit = await getUserSeatLimit(organization.id);
  if ((count ?? 0) >= limit) redirect("/equipe?erro=limite");

  const admin = createAdminClient();
  const { data: existingUserId, error: findError } = await admin.rpc("service_find_auth_user_id_by_email", { p_email: email });
  if (findError) redirect("/equipe?erro=config");

  let userId = existingUserId as string | null;
  let memberStatus: "active" | "invited" = "active";

  if (!userId) {
    const { data, error } = await admin.auth.admin.inviteUserByEmail(email, {
      redirectTo: `${getPublicAppUrl()}/auth/callback?next=/definir-senha`,
      data: { invited_to_organization: organization.id }
    });
    if (error || !data.user) redirect("/equipe?erro=convite");
    userId = data.user.id;
    memberStatus = data.user.email_confirmed_at ? "active" : "invited";
  }

  const { error: memberError } = await admin.rpc("service_add_organization_member", {
    p_organization_id: organization.id,
    p_user_id: userId,
    p_role: role,
    p_status: memberStatus
  });
  if (memberError) redirect("/equipe?erro=salvar");

  await admin.from("audit_logs").insert({
    organization_id: organization.id,
    actor_user_id: user.id,
    action: "organization.member_invited",
    entity_type: "organization_member",
    entity_id: userId,
    metadata: { email, role, status: memberStatus }
  });

  revalidatePath("/equipe");
  redirect(memberStatus === "invited" ? "/equipe?status=convite-enviado" : "/equipe?status=membro-adicionado");
}

export async function manageMemberAction(formData: FormData) {
  const { organization } = await requireTeamAdmin();
  const userId = text(formData, "user_id", 80);
  const action = text(formData, "member_action", 20);
  const role = text(formData, "role", 30) || null;
  if (!userId || !["role", "enable", "disable", "remove"].includes(action)) redirect("/equipe?erro=campos");

  const supabase = await createClient();
  const { error } = await supabase.rpc("manage_organization_member", {
    p_organization_id: organization.id,
    p_user_id: userId,
    p_action: action,
    p_role: role
  });
  if (error) redirect("/equipe?erro=permissao");

  revalidatePath("/equipe");
  redirect("/equipe?status=atualizado");
}
