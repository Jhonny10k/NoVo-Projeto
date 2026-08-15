import Link from "next/link";
import { DashboardNav } from "@/components/dashboard/nav";
import { convertLeadToCustomerAction, createLeadAction, moveLeadStageAction, updatePipelineStageAction } from "@/features/crm/actions";
import { requireUser } from "@/lib/auth/require-user";
import { formatDate, formatMoney } from "@/lib/format";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { hasFeature, requireFeature } from "@/lib/plans/entitlements";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

type Stage = { id: string; name: string; stage_key: string; sort_order: number; is_closed: boolean; is_won: boolean };
type Lead = { id: string; unit_id: string | null; name: string; whatsapp: string | null; email: string | null; stage_id: string | null; status: string; source: string; interest: string | null; potential_value_cents: number | null; created_at: string };
type UnitOption = { id:string; name:string; code:string; is_headquarters:boolean };

export default async function CrmPage({searchParams }: Props) {
  await requireFeature("crm");
  const canExport = await hasFeature("exports");
  await requireUser();
  const organization = await requireCurrentOrganization();
  const supabase = await createClient();
  const { data: pipeline } = await supabase.from("pipelines").select("id").eq("organization_id", organization.id).eq("is_default", true).limit(1).maybeSingle();
  const [{ data: stages }, { data: leads }, { data: unitsData }] = await Promise.all([
    pipeline ? supabase.from("pipeline_stages").select("id,name,stage_key,sort_order,is_closed,is_won").eq("organization_id", organization.id).eq("pipeline_id", pipeline.id).order("sort_order") : Promise.resolve({ data: [] as Stage[], error: null }),
    supabase.from("leads").select("id,unit_id,name,whatsapp,email,stage_id,status,source,interest,potential_value_cents,created_at").eq("organization_id", organization.id).order("created_at", { ascending: false }).limit(200),
    supabase.rpc("list_accessible_units",{p_organization_id:organization.id})
  ]);
  const params = await searchParams;
  const status = typeof params.status === "string" ? params.status : "";
  const error = typeof params.erro === "string" ? params.erro : "";
  const allStages = (stages ?? []) as Stage[];
  const allLeads = (leads ?? []) as Lead[];
  const units=(unitsData??[]) as UnitOption[];
  const unitNames=new Map(units.map(unit=>[unit.id,unit.name]));

  return <>
    <DashboardNav organizationName={organization.name} />
    <main className="container-shell py-10">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div><p className="text-sm font-bold uppercase tracking-widest text-blue-700">CRM</p><h1 className="mt-1 text-3xl font-black">Funil comercial</h1><div className="mt-4">{canExport ? <Link href="/api/export/leads" className="btn-secondary">Exportar leads</Link> : <Link href="/assinatura?recurso=exports" className="btn-secondary">Liberar exportação</Link>}</div><p className="muted mt-2">Mova cada lead entre as etapas e converta negócios fechados em clientes.</p></div>
        <Link href="/clientes" className="btn-secondary">Ver clientes</Link>
      </div>
      {status ? <p className="mt-5 rounded-xl bg-emerald-50 p-4 text-sm font-semibold">Lead salvo.</p> : null}
      {error ? <p role="alert" className="mt-5 rounded-xl bg-amber-50 p-4 text-sm">Não foi possível concluir a ação.</p> : null}

      {organization.role === "owner" || organization.role === "admin" ? <details className="card mt-6 p-5"><summary className="cursor-pointer font-black">Configurar etapas do funil</summary><p className="muted mt-2 text-sm">Renomeie e reordene as etapas padrão sem alterar as chaves internas usadas pelos fluxos.</p><div className="mt-4 grid gap-3 md:grid-cols-2">{allStages.map((stage) => <form action={updatePipelineStageAction} key={stage.id} className="rounded-xl border border-black/10 p-3"><input type="hidden" name="stage_id" value={stage.id} /><div className="grid grid-cols-[1fr_90px] gap-2"><label className="field"><span>Nome</span><input name="name" defaultValue={stage.name} maxLength={100} required /></label><label className="field"><span>Ordem</span><input name="sort_order" type="number" min="0" max="10000" defaultValue={stage.sort_order} /></label></div><button className="btn-secondary mt-3" type="submit">Salvar etapa</button></form>)}</div></details> : null}

      <details className="card mt-7 p-5">
        <summary className="cursor-pointer font-bold">+ Adicionar lead manualmente</summary>
        <form action={createLeadAction} className="mt-5 grid gap-4 md:grid-cols-2">
          <label className="field"><span>Nome</span><input name="name" minLength={2} required /></label>
          <label className="field"><span>WhatsApp</span><input name="whatsapp" inputMode="tel" /></label>
          <label className="field"><span>E-mail</span><input name="email" type="email" /></label>
          <label className="field"><span>Valor potencial (R$)</span><input name="potential_value" inputMode="decimal" /></label>
          {units.length ? <label className="field"><span>Unidade</span><select name="unit_id" defaultValue=""><option value="">Escopo geral</option>{units.map(unit=><option key={unit.id} value={unit.id}>{unit.name} ({unit.code})</option>)}</select></label> : null}
          <label className={units.length?"field":"field md:col-span-2"}><span>Interesse</span><textarea name="interest" /></label>
          <button className="btn-primary md:w-fit" type="submit">Criar lead</button>
        </form>
      </details>

      <section className="mt-8 overflow-x-auto pb-4">
        <div className="grid min-w-[1200px] grid-cols-7 gap-4">
          {allStages.map((stage) => {
            const stageLeads = allLeads.filter((lead) => lead.stage_id === stage.id || (!lead.stage_id && lead.status === stage.stage_key));
            return <section key={stage.id} className="rounded-2xl border border-black/5 bg-black/[.025] p-3">
              <div className="flex items-center justify-between gap-2"><h2 className="font-black">{stage.name}</h2><span className="rounded-full bg-white px-2 py-1 text-xs font-bold">{stageLeads.length}</span></div>
              <div className="mt-3 grid gap-3">
                {stageLeads.map((lead) => <article key={lead.id} className="card p-4">
                  <h3 className="font-bold"><Link href={`/crm/${lead.id}`} className="hover:text-blue-700">{lead.name}</Link></h3>
                  <p className="muted mt-1 text-xs">{lead.whatsapp || lead.email || "Sem contato"}</p>{lead.unit_id?<p className="mt-1 text-[11px] font-bold uppercase tracking-wide text-blue-700">{unitNames.get(lead.unit_id)??"Unidade"}</p>:null}
                  {lead.interest ? <p className="mt-3 text-sm">{lead.interest}</p> : null}
                  <div className="mt-3 flex items-center justify-between gap-2 text-xs"><span>{formatMoney(lead.potential_value_cents)}</span><span className="muted">{formatDate(lead.created_at)}</span></div>
                  <form action={moveLeadStageAction} className="mt-4 grid gap-2">
                    <input type="hidden" name="lead_id" value={lead.id} />
                    <select name="stage_id" defaultValue={stage.id} className="min-h-10 rounded-lg border border-black/10 bg-white px-2 text-sm">
                      {allStages.map((option) => <option key={option.id} value={option.id}>{option.name}</option>)}
                    </select>
                    <button className="btn-secondary min-h-10 text-sm" type="submit">Mover</button>
                  </form>
                  {stage.is_won ? <form action={convertLeadToCustomerAction} className="mt-2"><input type="hidden" name="lead_id" value={lead.id} /><button className="btn-primary min-h-10 w-full text-sm" type="submit">Converter em cliente</button></form> : null}
                  <div className="mt-2 flex justify-between gap-2 text-xs font-bold text-blue-700"><Link href={`/crm/${lead.id}`}>Ver histórico</Link><Link href={`/orcamentos?lead=${lead.id}`}>Criar orçamento</Link></div>
                </article>)}
                {stageLeads.length === 0 ? <p className="muted rounded-xl border border-dashed border-black/10 p-4 text-center text-xs">Nenhum lead</p> : null}
              </div>
            </section>;
          })}
        </div>
      </section>
    </main>
  </>;
}
