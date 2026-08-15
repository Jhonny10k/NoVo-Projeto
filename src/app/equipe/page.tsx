import { DashboardNav } from "@/components/dashboard/nav";
import { inviteMemberAction, manageMemberAction } from "@/features/team/actions";
import { requireUser } from "@/lib/auth/require-user";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };
type Member = {
  user_id: string;
  role: string;
  status: string;
  full_name: string | null;
  email: string | null;
  email_confirmed: boolean;
};

const roleNames: Record<string, string> = {
  owner: "Proprietário",
  admin: "Administrador",
  sales: "Vendedor",
  support: "Atendimento",
  viewer: "Visualização"
};

export default async function TeamPage({ searchParams }: Props) {
  await requireUser();
  const organization = await requireCurrentOrganization();
  const params = await searchParams;
  if (!["owner", "admin"].includes(organization.role)) {
    return <><DashboardNav organizationName={organization.name} /><main className="container-shell py-10"><div className="card p-6"><h1 className="text-2xl font-black">Equipe</h1><p className="muted mt-2">Somente proprietários e administradores podem gerenciar usuários.</p></div></main></>;
  }

  const supabase = await createClient();
  const { data } = await supabase.rpc("organization_member_directory", { p_organization_id: organization.id });
  const members = (data ?? []) as Member[];
  const status = typeof params.status === "string" ? params.status : "";
  const error = typeof params.erro === "string" ? params.erro : "";

  return <>
    <DashboardNav organizationName={organization.name} />
    <main className="container-shell py-10">
      <div><p className="text-sm font-bold uppercase tracking-widest text-blue-700">Acessos</p><h1 className="mt-1 text-3xl font-black">Equipe</h1><p className="muted mt-2">Convide usuários e controle o nível de acesso sem compartilhar senhas.</p></div>
      {status ? <p className="mt-5 rounded-xl bg-emerald-50 p-4 text-sm font-semibold">Alteração concluída.</p> : null}
      {error === "limite" ? <p role="alert" className="mt-5 rounded-xl bg-amber-50 p-4 text-sm">O limite de usuários do plano atual foi atingido.</p> : error ? <p role="alert" className="mt-5 rounded-xl bg-amber-50 p-4 text-sm">Não foi possível concluir. Verifique dados, permissões e configuração de e-mail.</p> : null}

      <section className="card mt-7 p-6">
        <h2 className="text-xl font-black">Convidar pessoa</h2>
        <form action={inviteMemberAction} className="mt-4 grid gap-4 md:grid-cols-[1fr_220px_auto] md:items-end">
          <label className="field"><span>E-mail</span><input name="email" type="email" required /></label>
          <label className="field"><span>Função</span><select name="role" defaultValue="sales"><option value="admin">Administrador</option><option value="sales">Vendedor</option><option value="support">Atendimento</option><option value="viewer">Visualização</option></select></label>
          <button className="btn-primary" type="submit">Enviar convite</button>
        </form>
      </section>

      <section className="mt-8">
        <h2 className="text-xl font-black">Usuários</h2>
        <div className="mt-4 grid gap-4">
          {members.map((member) => <article key={member.user_id} className="card grid gap-4 p-5 lg:grid-cols-[1fr_auto] lg:items-center">
            <div><p className="font-bold">{member.full_name || member.email || "Usuário"}</p><p className="muted mt-1 text-sm">{member.email}</p><p className="mt-2 text-xs font-semibold uppercase tracking-wide">{roleNames[member.role] ?? member.role} · {member.status === "active" ? "Ativo" : member.status === "invited" ? "Convite pendente" : "Desativado"}</p></div>
            <form action={manageMemberAction} className="flex flex-wrap items-end gap-2">
              <input type="hidden" name="user_id" value={member.user_id} />
              {member.role !== "owner" ? <><label className="field min-w-44"><span>Função</span><select name="role" defaultValue={member.role}><option value="admin">Administrador</option><option value="sales">Vendedor</option><option value="support">Atendimento</option><option value="viewer">Visualização</option></select></label><button className="btn-secondary" type="submit" name="member_action" value="role">Salvar função</button></> : null}
              {member.role !== "owner" && member.status === "active" ? <button className="btn-secondary" type="submit" name="member_action" value="disable">Desativar</button> : null}
              {member.role !== "owner" && member.status === "disabled" ? <button className="btn-secondary" type="submit" name="member_action" value="enable">Reativar</button> : null}
              {member.role !== "owner" ? <button className="btn-danger" type="submit" name="member_action" value="remove">Remover</button> : null}
            </form>
          </article>)}
        </div>
      </section>
    </main>
  </>;
}
