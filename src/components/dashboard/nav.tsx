import Link from "next/link";
import { signOutAction } from "@/features/auth/actions";
import { getCurrentOrganization } from "@/lib/organizations/current";
import { createClient } from "@/lib/supabase/server";

export async function DashboardNav({ organizationName }: { organizationName: string }) {
  const organization=await getCurrentOrganization();let branding:{brand_name:string|null;logo_url:string|null;primary_color:string|null}|null=null;
  if(organization){try{const supabase=await createClient();const {data}=await supabase.from("organization_branding").select("brand_name,logo_url,primary_color").eq("organization_id",organization.id).maybeSingle();branding=data;}catch{}}
  const displayName=branding?.brand_name||organizationName;
  return (
    <header className="border-b border-black/5 bg-white" style={branding?.primary_color?{borderTop:`3px solid ${branding.primary_color}`}:{}}>
      <div className="container-shell flex min-h-16 flex-wrap items-center justify-between gap-3 py-2">
        <div className="flex items-center gap-3">{branding?.logo_url?<img src={branding.logo_url} alt="" className="h-9 w-9 rounded-lg object-contain"/>:null}<div><Link href="/dashboard" className="font-extrabold">{displayName}</Link><p className="muted text-xs">Painel da empresa</p></div></div>
        <nav className="flex flex-wrap items-center gap-x-4 gap-y-2" aria-label="Painel">
          <Link href="/dashboard" className="text-sm font-semibold">Hoje</Link>
          <Link href="/crm" className="text-sm font-semibold">CRM</Link>
          <Link href="/atendimento" className="text-sm font-semibold">Atendimento</Link>
          <Link href="/clientes" className="text-sm font-semibold">Clientes</Link>
          <Link href="/orcamentos" className="text-sm font-semibold">Orçamentos</Link>
          <Link href="/tarefas" className="text-sm font-semibold">Tarefas</Link>
          <Link href="/agenda" className="text-sm font-semibold">Agenda</Link>
          <Link href="/automacoes" className="text-sm font-semibold">Automações</Link>
          <Link href="/analytics" className="text-sm font-semibold">Analytics</Link>
          <Link href="/assistente-ia" className="text-sm font-semibold">Assistente IA</Link>
          <Link href="/catalogo" className="text-sm font-semibold">Catálogo</Link>
          <Link href="/site" className="text-sm font-semibold">Site</Link>
          <Link href="/notificacoes" className="text-sm font-semibold">Notificações</Link>
          <Link href="/integracoes" className="text-sm font-semibold">Integrações</Link>
          <Link href="/desenvolvedores" className="text-sm font-semibold">Desenvolvedores</Link>
          <Link href="/white-label" className="text-sm font-semibold">Marca</Link>
          <Link href="/equipe" className="text-sm font-semibold">Equipe</Link>
          <Link href="/unidades" className="text-sm font-semibold">Unidades</Link>
          <Link href="/assinatura" className="text-sm font-semibold">Plano</Link>
          <Link href="/configuracoes" className="text-sm font-semibold">Empresa</Link>
          <Link href="/perfil" className="text-sm font-semibold">Perfil</Link>
          <form action={signOutAction}><button type="submit" className="btn-secondary">Sair</button></form>
        </nav>
      </div>
    </header>
  );
}
