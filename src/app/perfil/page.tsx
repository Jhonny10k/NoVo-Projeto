import { DashboardNav } from "@/components/dashboard/nav";
import { updateProfileAction } from "@/features/profile/actions";
import { requireUser } from "@/lib/auth/require-user";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";
type Props = { searchParams: Promise<Record<string,string|string[]|undefined>> };
type Preferences = { leads?:boolean; quotes?:boolean; appointments?:boolean; billing?:boolean };

export default async function ProfilePage({ searchParams }: Props) {
  const user = await requireUser();
  const organization = await requireCurrentOrganization();
  const supabase = await createClient();
  const { data: profile } = await supabase.from("profiles").select("full_name,avatar_url,phone,job_title,notification_preferences").eq("id", user.id).maybeSingle();
  const params = await searchParams;
  const status = typeof params.status === "string" ? params.status : "";
  const error = typeof params.erro === "string" ? params.erro : "";
  const preferences = (profile?.notification_preferences ?? {}) as Preferences;
  return <><DashboardNav organizationName={organization.name}/><main className="container-shell py-10">
    <p className="text-sm font-bold uppercase tracking-widest text-blue-700">Perfil</p><h1 className="mt-1 text-3xl font-black">Sua conta</h1><p className="muted mt-2">Dados pessoais e preferências de notificação. Seu e-mail de acesso é gerenciado pelo Supabase Auth.</p>
    {status ? <p className="mt-5 rounded-xl bg-emerald-50 p-4 text-sm font-semibold">Perfil atualizado.</p> : null}{error ? <p className="mt-5 rounded-xl bg-amber-50 p-4 text-sm">Não foi possível salvar. Revise os dados.</p> : null}
    <form action={updateProfileAction} className="card mt-7 grid gap-5 p-6 lg:grid-cols-2">
      <div className="lg:col-span-2 flex items-center gap-4">{profile?.avatar_url ? <img src={profile.avatar_url} alt="Foto do perfil" className="h-20 w-20 rounded-full object-cover"/> : <div className="flex h-20 w-20 items-center justify-center rounded-full bg-black/5 text-2xl font-black">{(profile?.full_name || user.email || "U").slice(0,1).toUpperCase()}</div>}<label className="field flex-1"><span>Foto</span><input type="file" name="avatar" accept="image/jpeg,image/png,image/webp"/><small className="muted">JPG, PNG ou WebP, até 5 MB.</small></label></div>
      <label className="field"><span>Nome</span><input name="full_name" required maxLength={120} defaultValue={profile?.full_name ?? ""}/></label><label className="field"><span>E-mail</span><input value={user.email ?? ""} disabled/></label><label className="field"><span>Telefone</span><input name="phone" maxLength={40} defaultValue={profile?.phone ?? ""}/></label><label className="field"><span>Cargo/função</span><input name="job_title" maxLength={100} defaultValue={profile?.job_title ?? ""}/></label>
      <fieldset className="rounded-xl border border-black/10 p-4 lg:col-span-2"><legend className="px-2 font-bold">Notificações</legend><div className="grid gap-3 sm:grid-cols-2"><label><input type="checkbox" name="notify_leads" defaultChecked={preferences.leads !== false}/> Novos leads</label><label><input type="checkbox" name="notify_quotes" defaultChecked={preferences.quotes !== false}/> Orçamentos</label><label><input type="checkbox" name="notify_appointments" defaultChecked={preferences.appointments !== false}/> Agenda</label><label><input type="checkbox" name="notify_billing" defaultChecked={preferences.billing !== false}/> Cobrança</label></div></fieldset>
      <button className="btn-primary lg:col-span-2 lg:justify-self-start" type="submit">Salvar perfil</button>
    </form>
  </main></>;
}
