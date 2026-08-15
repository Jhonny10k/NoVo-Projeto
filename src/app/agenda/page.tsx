import Link from "next/link";
import { DashboardNav } from "@/components/dashboard/nav";
import { createAppointmentAction, saveBookingSettingsAction, updateAppointmentStatusAction } from "@/features/appointments/actions";
import { requireUser } from "@/lib/auth/require-user";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { requireFeature } from "@/lib/plans/entitlements";
import { createClient } from "@/lib/supabase/server";
import { isoTimeAgo } from "@/lib/time";

export const dynamic = "force-dynamic";

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };
type Member = { user_id: string; full_name: string | null; email: string | null; status: string };
type Appointment = { id: string; starts_at: string; ends_at: string; status: string; source: string; professional_user_id: string | null; contact_name: string | null; services: { name: string } | { name: string }[] | null; leads: { name: string } | { name: string }[] | null; customers: { name: string } | { name: string }[] | null };
const days = [[1, "Segunda"], [2, "Terça"], [3, "Quarta"], [4, "Quinta"], [5, "Sexta"], [6, "Sábado"], [7, "Domingo"]] as const;
const first = <T,>(value: T | T[] | null) => Array.isArray(value) ? value[0] ?? null : value;

const appointmentStatus: Record<string, string> = {
  scheduled: "Agendado",
  confirmed: "Confirmado",
  completed: "Concluído",
  canceled: "Cancelado",
  no_show: "Não compareceu"
};

export default async function AgendaPage({ searchParams }: Props) {
  await requireUser();
  await requireFeature("appointments");
  const organization = await requireCurrentOrganization();
  const supabase = await createClient();
  const params = await searchParams;

  const [{ data: settings }, { data: services }, { data: leads }, { data: customers }, { data: appointments }, { data: membersData }, { data: orgData }] = await Promise.all([
    supabase.from("booking_settings").select("enabled,slot_duration_minutes,buffer_minutes,availability").eq("organization_id", organization.id).maybeSingle(),
    supabase.from("services").select("id,name,duration_minutes").eq("organization_id", organization.id).eq("active", true).order("name"),
    supabase.from("leads").select("id,name").eq("organization_id", organization.id).not("status", "in", "(won,lost)").order("created_at", { ascending: false }).limit(100),
    supabase.from("customers").select("id,name").eq("organization_id", organization.id).order("created_at", { ascending: false }).limit(100),
    supabase.from("appointments").select("id,starts_at,ends_at,status,source,professional_user_id,contact_name,services(name),leads(name),customers(name)").eq("organization_id", organization.id).gte("ends_at", isoTimeAgo(86400000)).order("starts_at").limit(200),
    supabase.rpc("organization_member_directory", { p_organization_id: organization.id }),
    supabase.from("organizations").select("timezone").eq("id", organization.id).single()
  ]);

  const members = ((membersData ?? []) as Member[]).filter((member) => member.status === "active");
  const allAppointments = (appointments ?? []) as Appointment[];
  const timeZone = orgData?.timezone || "America/Sao_Paulo";
  const availability = (settings?.availability ?? {}) as Record<string, string[][]>;
  const status = typeof params.status === "string" ? params.status : "";
  const error = typeof params.erro === "string" ? params.erro : "";
  const canManage = ["owner", "admin"].includes(organization.role);
  const scheduledCount = allAppointments.filter((appointment) => ["scheduled", "confirmed"].includes(appointment.status)).length;

  return (
    <>
      <DashboardNav organizationName={organization.name} />
      <main className="container-shell pb-14 pt-7 sm:pt-10">
        <section className="flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
          <div className="max-w-3xl">
            <p className="eyebrow">Operação</p>
            <h1 className="page-title mt-4">Agenda</h1>
            <p className="muted mt-3 max-w-2xl leading-7">Organize compromissos por horário e deixe configurações de disponibilidade separadas da rotina diária.</p>
          </div>
          <div className="flex flex-col gap-2 sm:flex-row">
            <Link href="/agenda/calendario" className="btn-secondary">Ver calendário</Link>
            {settings?.enabled ? <Link href={`/agendar/${organization.slug}`} className="btn-secondary">Página pública</Link> : null}
          </div>
        </section>

        {status ? <p className="mt-5 rounded-xl border border-emerald-100 bg-emerald-50 p-4 text-sm font-semibold text-emerald-800">Alteração concluída.</p> : null}
        {error ? <p role="alert" className="mt-5 rounded-xl border border-amber-100 bg-amber-50 p-4 text-sm text-amber-900">{error === "conflito" ? "O profissional já possui compromisso nesse horário." : error === "horario" ? "Revise os horários de disponibilidade." : "Não foi possível concluir a operação."}</p> : null}

        <section className="mt-7 grid grid-cols-2 gap-3 sm:grid-cols-4 lg:max-w-3xl">
          <div className="soft-panel p-4"><p className="text-xs font-semibold text-slate-500">Próximos registros</p><p className="mt-1 text-2xl font-extrabold">{allAppointments.length}</p></div>
          <div className="soft-panel p-4"><p className="text-xs font-semibold text-slate-500">Ativos</p><p className="mt-1 text-2xl font-extrabold">{scheduledCount}</p></div>
          <div className="soft-panel p-4"><p className="text-xs font-semibold text-slate-500">Profissionais</p><p className="mt-1 text-2xl font-extrabold">{members.length}</p></div>
          <div className="soft-panel p-4"><p className="text-xs font-semibold text-slate-500">Agendamento online</p><p className={`mt-2 text-sm font-extrabold ${settings?.enabled ? "text-emerald-700" : "text-slate-500"}`}>{settings?.enabled ? "Ativo" : "Desativado"}</p></div>
        </section>

        <section className="mt-6 grid gap-4 lg:grid-cols-2">
          <details className="card overflow-hidden">
            <summary className="flex min-h-16 items-center justify-between gap-3 px-5 py-4 sm:px-6">
              <span><span className="block font-extrabold">Novo agendamento interno</span><span className="muted mt-1 block text-xs font-medium">Crie um compromisso manualmente.</span></span>
              <span className="grid h-9 w-9 place-items-center rounded-xl bg-blue-50 font-bold text-blue-700" aria-hidden="true">＋</span>
            </summary>
            <form action={createAppointmentAction} className="grid gap-4 border-t border-slate-100 px-5 pb-6 pt-5 sm:grid-cols-2 sm:px-6">
              <label className="field"><span>Data e hora</span><input type="datetime-local" name="start" required /></label>
              <label className="field"><span>Duração (min)</span><input type="number" name="duration_minutes" min="15" max="480" placeholder="Usa a duração do serviço" /></label>
              <label className="field"><span>Serviço</span><select name="service_id" defaultValue=""><option value="">Sem serviço</option>{(services ?? []).map((service) => <option key={service.id} value={service.id}>{service.name}</option>)}</select></label>
              <label className="field"><span>Profissional</span><select name="professional_user_id" defaultValue=""><option value="">Não atribuído</option>{members.map((member) => <option key={member.user_id} value={member.user_id}>{member.full_name || member.email || "Usuário"}</option>)}</select></label>
              <label className="field"><span>Lead</span><select name="lead_id" defaultValue=""><option value="">Nenhum</option>{(leads ?? []).map((lead) => <option key={lead.id} value={lead.id}>{lead.name}</option>)}</select></label>
              <label className="field"><span>Cliente</span><select name="customer_id" defaultValue=""><option value="">Nenhum</option>{(customers ?? []).map((customer) => <option key={customer.id} value={customer.id}>{customer.name}</option>)}</select></label>
              <label className="field sm:col-span-2"><span>Observações</span><textarea name="notes" maxLength={2000} /></label>
              <button className="btn-primary sm:w-fit" type="submit">Adicionar à agenda</button>
            </form>
          </details>

          {canManage ? (
            <details className="card overflow-hidden">
              <summary className="flex min-h-16 items-center justify-between gap-3 px-5 py-4 sm:px-6">
                <span><span className="block font-extrabold">Disponibilidade pública</span><span className="muted mt-1 block text-xs font-medium">Horários que clientes podem reservar.</span></span>
                <span className={`rounded-full px-2.5 py-1 text-[.68rem] font-extrabold ${settings?.enabled ? "bg-emerald-50 text-emerald-700" : "bg-slate-100 text-slate-500"}`}>{settings?.enabled ? "Ativa" : "Inativa"}</span>
              </summary>
              <form action={saveBookingSettingsAction} className="grid gap-5 border-t border-slate-100 px-5 pb-6 pt-5 sm:px-6">
                <div className="grid gap-4 sm:grid-cols-2"><label className="field"><span>Duração padrão</span><input type="number" name="slot_duration_minutes" min="15" max="480" defaultValue={settings?.slot_duration_minutes ?? 60} /></label><label className="field"><span>Intervalo</span><input type="number" name="buffer_minutes" min="0" max="180" defaultValue={settings?.buffer_minutes ?? 0} /></label></div>
                <label className="flex min-h-11 items-center gap-3 rounded-xl border border-slate-200 bg-slate-50 px-3 text-sm font-semibold"><input type="checkbox" name="enabled" defaultChecked={settings?.enabled === true} />Aceitar agendamentos pelo site</label>
                <div className="grid gap-2">
                  {days.map(([day, label]) => {
                    const range = availability[String(day)]?.[0];
                    return (
                      <div key={day} className="soft-panel grid gap-3 p-3 sm:grid-cols-[135px_1fr_1fr] sm:items-end">
                        <label className="flex min-h-11 items-center gap-2 text-sm font-semibold"><input type="checkbox" name={`day_${day}_enabled`} defaultChecked={Boolean(range)} />{label}</label>
                        <label className="field"><span>Abre</span><input type="time" name={`day_${day}_start`} defaultValue={range?.[0] ?? "08:00"} /></label>
                        <label className="field"><span>Fecha</span><input type="time" name={`day_${day}_end`} defaultValue={range?.[1] ?? "18:00"} /></label>
                      </div>
                    );
                  })}
                </div>
                <button className="btn-secondary sm:w-fit" type="submit">Salvar disponibilidade</button>
              </form>
            </details>
          ) : (
            <div className="card p-5 sm:p-6"><p className="font-extrabold">Disponibilidade pública</p><p className="muted mt-2 text-sm leading-6">Somente owner ou admin pode alterar os horários de reserva do site.</p></div>
          )}
        </section>

        <section className="mt-9" aria-labelledby="appointments-title">
          <div className="mb-4 flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
            <div><h2 id="appointments-title" className="text-xl font-extrabold tracking-tight">Próximos compromissos</h2><p className="muted mt-1 text-sm">Horários exibidos em {timeZone}.</p></div>
            <Link href="/agenda/calendario" className="text-sm font-extrabold text-blue-700">Abrir visão de calendário →</Link>
          </div>
          <div className="grid gap-3">
            {allAppointments.map((appointment) => {
              const service = first(appointment.services);
              const lead = first(appointment.leads);
              const customer = first(appointment.customers);
              const professional = members.find((member) => member.user_id === appointment.professional_user_id);
              const startDate = new Intl.DateTimeFormat("pt-BR", { dateStyle: "medium", timeStyle: "short", timeZone }).format(new Date(appointment.starts_at));
              const endTime = new Intl.DateTimeFormat("pt-BR", { timeStyle: "short", timeZone }).format(new Date(appointment.ends_at));

              return (
                <article key={appointment.id} className="card p-4 sm:p-5">
                  <div className="grid gap-4 lg:grid-cols-[1fr_auto] lg:items-center">
                    <div className="min-w-0">
                      <div className="flex flex-wrap items-center gap-2"><span className="rounded-full bg-blue-50 px-2.5 py-1 text-[.68rem] font-extrabold text-blue-700">{appointmentStatus[appointment.status] ?? appointment.status}</span><span className="text-xs font-semibold text-slate-400">{appointment.source === "public" ? "Reserva pelo site" : "Agendamento interno"}</span></div>
                      <h3 className="mt-2 truncate text-base font-extrabold">{customer?.name || lead?.name || appointment.contact_name || "Contato"}</h3>
                      <p className="mt-1 text-sm font-semibold text-slate-700">{startDate} → {endTime}</p>
                      <p className="muted mt-2 text-sm leading-6">{service?.name || "Sem serviço"} · {professional?.full_name || professional?.email || "Sem profissional atribuído"}</p>
                    </div>
                    <form action={updateAppointmentStatusAction} className="grid grid-cols-[1fr_auto] gap-2 sm:flex">
                      <input type="hidden" name="appointment_id" value={appointment.id} />
                      <select name="status" defaultValue={appointment.status} aria-label="Status do agendamento" className="min-h-11 min-w-0 rounded-xl border border-slate-200 bg-white px-3 text-sm">
                        <option value="scheduled">Agendado</option><option value="confirmed">Confirmado</option><option value="completed">Concluído</option><option value="canceled">Cancelado</option><option value="no_show">Não compareceu</option>
                      </select>
                      <button className="btn-secondary" type="submit">Salvar</button>
                    </form>
                  </div>
                </article>
              );
            })}
            {allAppointments.length === 0 ? <div className="card p-7 text-center sm:p-9"><h3 className="font-extrabold">Nenhum compromisso próximo</h3><p className="muted mt-2 text-sm">Crie um agendamento acima ou ative a página pública.</p></div> : null}
          </div>
        </section>
      </main>
    </>
  );
}
