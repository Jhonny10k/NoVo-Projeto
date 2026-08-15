import { DashboardNav } from "@/components/dashboard/nav";
import { setPasswordAction } from "@/features/auth/actions";
import { requireUser } from "@/lib/auth/require-user";
import { getCurrentOrganization } from "@/lib/organizations/current";

export default async function SetPasswordPage() {
  await requireUser();
  const organization = await getCurrentOrganization();
  return <>
    {organization ? <DashboardNav organizationName={organization.name} /> : null}
    <main className="container-shell py-16"><form action={setPasswordAction} className="card mx-auto grid max-w-lg gap-4 p-7"><h1 className="text-2xl font-black">Defina sua senha</h1><p className="muted text-sm">Crie uma senha para acessar novamente depois de aceitar o convite.</p><label className="field"><span>Nova senha</span><input name="password" type="password" minLength={8} autoComplete="new-password" required /></label><label className="field"><span>Confirmar senha</span><input name="confirm_password" type="password" minLength={8} autoComplete="new-password" required /></label><button className="btn-primary" type="submit">Salvar senha</button></form></main>
  </>;
}
