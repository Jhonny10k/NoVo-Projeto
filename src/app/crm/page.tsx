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
type UnitOption = { id: string; name: string; code: string; is_headquarters: boolean };

export default async function CrmPage({ searchParams }: Props) {
  await requireFeature("crm");
  const canExport = await hasFeature("exports");
  await requireUser();
  const organization = await requireCurrentOrganization();
  const supabase = await createClient();

  const { data: pipeline } = await supabase
    .from("pipelines")
    .select("id")
    .eq("organization_id", organization.id)
    .eq("is_default", true)
    .limit(1)
    .maybeSingle();

  const [{ data: stages }, { data: leads }, { data: unitsData }] = await Promise.all([
    pipeline
      ? supabase.from("pipeline_stages").select("id,name,stage_key,sort_order,is_closed,is_won").eq("organization_id", organization.id).eq("pipeline_id", pipeline.id).order("sort_order")
      : Promise.resolve({ data: [] as Stage[], error: null }),
    supabase.from("leads").select("id,unit_id,name,whatsapp,email,stage_id,status,source,interest,potential_value_cents,created_at").eq("organization_id", organization.id).order("created_at", { ascending: false }).limit(200),
    supabase.rpc("list_accessible_units", { p_organization_id: organization.id })
  ]);

  const params = await searchParams;
  const status = typeof params.status === "string" ? params.status : "";
  const error = typeof params.erro === "string" ? params.erro : "";
  const allStages = (stages ?? []) as Stage[];
  const allLeads = (leads ?? []) as Lead[];
  const units = (unitsData ?? []) as UnitOption[];
  const unitNames = new Map(units.map((unit) => [unit.id, unit.name]));
  const canManagePipeline = organization.role === "owner" || organization.role === "admin";
  const openPotential = allLeads.reduce((total, lead) => total + (lead.potential_value_cents ?? 0), 0);

  return (
    <>
      <DashboardNav organizationName={organization.name} />
      <main className="container-shell pb-14 pt-7 sm:pt-10">
        <section className="flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
          <div className="max-w-3xl">
            <p className="eyebrow">Vendas</p>
            <h1 className="page-title mt-4">Funil comercial</h1>
            <p className="muted mt-3 max-w-2xl leading-7">Acompanhe oportunidades por etapa e mantenha o próximo movimento de cada lead visível.</p>
          </div>
          <div className="flex flex-col gap-2 sm:flex-row">
            <Link href="/clientes" className="btn-secondary">Ver clientes</Link>
            {canExport ? <Link href="/api/export/leads" className="btn-secondary">Exportar leads</Link> : <Link href="/assinatura?recurso=exports" className="btn-secondary">Liberar exportação</Link>}
          </div>
        </section>

        {status ? <p className="mt-5 rounded-xl border border-emerald-100 bg-emerald-50 p-4 text-sm font-semibold text-emerald-800">Lead salvo.</p> : null}
        {error ? <p role="alert" className="mt-5 rounded-xl border border-amber-100 bg-amber-50 p-4 text-sm text-amber-900">Não foi possível concluir a ação.</p> : null}

        <section className="mt-7 grid grid-cols-2 gap-3 sm:grid-cols-3 lg:max-w-2xl">
          <div className="soft-panel p-4"><p className="text-xs font-semibold text-slate-500">Leads visíveis</p><p className="mt-1 text-2xl font-extrabold">{allLeads.length}</p></div>
          <div className="soft-panel p-4"><p className="text-xs font-semibold text-slate-500">Etapas do funil</p><p className="mt-1 text-2xl font-extrabold">{allStages.length}</p></div>
          <div className="soft-panel col-span-2 p-4 sm:col-span-1"><p className="text-xs font-semibold text-slate-500">Potencial visível</p><p className="mt-1 break-words text-2xl font-extrabold">{formatMoney(openPotential)}</p></div>
        </section>

        <section className="mt-6 grid gap-3 lg:grid-cols-2">
          <details className="card p-5">
            <summary className="flex items-center justify-between gap-3 font-extrabold">
              <span>Adicionar lead</span><span className="text-blue-600" aria-hidden="true">＋</span>
            </summary>
            <p className="muted mt-2 text-sm">Cadastre uma oportunidade que chegou fora dos canais automáticos.</p>
            <form action={createLeadAction} className="mt-5 grid gap-4 sm:grid-cols-2">
              <label className="field"><span>Nome</span><input name="name" minLength={2} required /></label>
              <label className="field"><span>WhatsApp</span><input name="whatsapp" inputMode="tel" /></label>
              <label className="field"><span>E-mail</span><input name="email" type="email" /></label>
              <label className="field"><span>Valor potencial (R$)</span><input name="potential_value" inputMode="decimal" /></label>
              {units.length ? <label className="field"><span>Unidade</span><select name="unit_id" defaultValue=""><option value="">Escopo geral</option>{units.map((unit) => <option key={unit.id} value={unit.id}>{unit.name} ({unit.code})</option>)}</select></label> : null}
              <label className={units.length ? "field" : "field sm:col-span-2"}><span>Interesse</span><textarea name="interest" /></label>
              <button className="btn-primary sm:w-fit" type="submit">Criar lead</button>
            </form>
          </details>

          {canManagePipeline ? (
            <details className="card p-5">
              <summary className="flex items-center justify-between gap-3 font-extrabold">
                <span>Configurar etapas do funil</span><span className="text-slate-400" aria-hidden="true">⚙</span>
              </summary>
              <p className="muted mt-2 text-sm">Renomeie e reordene etapas sem alterar as chaves internas dos fluxos.</p>
              <div className="mt-4 grid gap-3">
                {allStages.map((stage) => (
                  <form action={updatePipelineStageAction} key={stage.id} className="soft-panel p-3">
                    <input type="hidden" name="stage_id" value={stage.id} />
                    <div className="grid gap-2 sm:grid-cols-[1fr_90px]">
                      <label className="field"><span>Nome</span><input name="name" defaultValue={stage.name} maxLength={100} required /></label>
                      <label className="field"><span>Ordem</span><input name="sort_order" type="number" min="0" max="10000" defaultValue={stage.sort_order} /></label>
                    </div>
                    <button className="btn-secondary mt-3" type="submit">Salvar etapa</button>
                  </form>
                ))}
              </div>
            </details>
          ) : (
            <div className="card p-5"><p className="font-extrabold">Seu funil está pronto para uso</p><p className="muted mt-2 text-sm leading-6">Administradores podem ajustar nomes e ordem das etapas nas configurações do CRM.</p></div>
          )}
        </section>

        <section className="mt-8" aria-labelledby="pipeline-title">
          <div className="mb-4 flex items-end justify-between gap-4">
            <div><h2 id="pipeline-title" className="text-xl font-extrabold tracking-tight">Pipeline</h2><p className="muted mt-1 text-sm">No celular, deslize horizontalmente entre as etapas.</p></div>
          </div>
          <div className="snap-x snap-mandatory overflow-x-auto pb-5">
            <div className="flex min-w-max gap-3 sm:gap-4">
              {allStages.map((stage) => {
                const stageLeads = allLeads.filter((lead) => lead.stage_id === stage.id || (!lead.stage_id && lead.status === stage.stage_key));
                const stageValue = stageLeads.reduce((total, lead) => total + (lead.potential_value_cents ?? 0), 0);
                return (
                  <section key={stage.id} className="w-[82vw] max-w-[320px] shrink-0 snap-start rounded-2xl border border-slate-200 bg-slate-100/70 p-3 sm:w-[300px]">
                    <header className="px-1 pb-3">
                      <div className="flex items-center justify-between gap-2"><h3 className="font-extrabold tracking-tight">{stage.name}</h3><span className="rounded-full bg-white px-2.5 py-1 text-xs font-extrabold text-slate-600 shadow-sm">{stageLeads.length}</span></div>
                      <p className="mt-1 text-xs font-medium text-slate-500">{formatMoney(stageValue)}</p>
                    </header>
                    <div className="grid gap-3">
                      {stageLeads.map((lead) => (
                        <article key={lead.id} className="card p-4">
                          <div className="flex items-start justify-between gap-3">
                            <div className="min-w-0"><h4 className="truncate font-extrabold"><Link href={`/crm/${lead.id}`} className="hover:text-blue-700">{lead.name}</Link></h4><p className="muted mt-1 truncate text-xs">{lead.whatsapp || lead.email || "Sem contato"}</p></div>
                            <span className="shrink-0 text-xs font-bold text-slate-500">{formatDate(lead.created_at)}</span>
                          </div>
                          {lead.unit_id ? <p className="mt-2 text-[.68rem] font-extrabold uppercase tracking-[.08em] text-blue-700">{unitNames.get(lead.unit_id) ?? "Unidade"}</p> : null}
                          {lead.interest ? <p className="mt-3 line-clamp-2 text-sm leading-6 text-slate-600">{lead.interest}</p> : null}
                          <p className="mt-3 text-sm font-extrabold text-slate-900">{formatMoney(lead.potential_value_cents)}</p>
                          <form action={moveLeadStageAction} className="mt-4 grid grid-cols-[1fr_auto] gap-2">
                            <input type="hidden" name="lead_id" value={lead.id} />
                            <select name="stage_id" defaultValue={stage.id} aria-label={`Mover ${lead.name} para etapa`} className="min-h-10 min-w-0 rounded-lg border border-slate-200 bg-white px-2 text-sm">
                              {allStages.map((option) => <option key={option.id} value={option.id}>{option.name}</option>)}
                            </select>
                            <button className="btn-secondary min-h-10 px-3 text-sm" type="submit">Mover</button>
                          </form>
                          {stage.is_won ? <form action={convertLeadToCustomerAction} className="mt-2"><input type="hidden" name="lead_id" value={lead.id} /><button className="btn-primary min-h-10 w-full text-sm" type="submit">Converter em cliente</button></form> : null}
                          <div className="mt-3 flex flex-wrap items-center justify-between gap-2 text-xs font-extrabold text-blue-700"><Link href={`/crm/${lead.id}`}>Histórico</Link><Link href={`/orcamentos?lead=${lead.id}`}>Novo orçamento</Link></div>
                        </article>
                      ))}
                      {stageLeads.length === 0 ? <div className="rounded-xl border border-dashed border-slate-300 bg-white/60 p-5 text-center"><p className="text-xs font-semibold text-slate-500">Nenhum lead nesta etapa</p></div> : null}
                    </div>
                  </section>
                );
              })}
            </div>
          </div>
        </section>
      </main>
    </>
  );
}
