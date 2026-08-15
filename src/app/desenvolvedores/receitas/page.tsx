import Link from "next/link";
import { DashboardNav } from "@/components/dashboard/nav";
import { requireCurrentOrganization } from "@/lib/organizations/current";

export const dynamic="force-dynamic";

const apiExample=`GET https://SEU_DOMINIO/api/v1/leads?limit=50\nAuthorization: Bearer nd_live_...`;
const webhookHeaders=`X-ND-Event: lead_created\nX-ND-Delivery: <uuid>\nX-ND-Timestamp: <unix_seconds>\nX-ND-Signature: v1=<hmac_sha256>`;

export default async function IntegrationRecipesPage(){
  const organization=await requireCurrentOrganization();
  return <><DashboardNav organizationName={organization.name}/><main className="container-shell py-10">
    <div className="flex flex-wrap items-end justify-between gap-4"><div><p className="text-sm font-bold uppercase tracking-widest text-blue-700">Integrações</p><h1 className="mt-1 text-3xl font-black">Receitas para Zapier, Make e n8n</h1><p className="muted mt-2 max-w-3xl">Use HTTP/API e Webhooks padrão. Não existe adapter especial escondido: a mesma autenticação, quota, assinatura e idempotência valem para qualquer plataforma.</p></div><Link href="/desenvolvedores" className="btn-secondary">Voltar para API e Webhooks</Link></div>

    <section className="mt-8 grid gap-4 lg:grid-cols-3">
      <article className="card p-6"><p className="text-xs font-bold uppercase tracking-wide text-blue-700">Zapier</p><h2 className="mt-2 text-xl font-black">Receber evento</h2><ol className="muted mt-4 list-decimal space-y-2 pl-5 text-sm"><li>Crie um Catch Hook no Zapier.</li><li>Cadastre a URL HTTPS em Webhooks outbound.</li><li>Escolha somente os eventos necessários.</li><li>Valide a assinatura HMAC antes de executar ações sensíveis quando o fluxo permitir código.</li><li>Use <code>X-ND-Delivery</code> como chave de idempotência.</li></ol></article>
      <article className="card p-6"><p className="text-xs font-bold uppercase tracking-wide text-blue-700">Make</p><h2 className="mt-2 text-xl font-black">Consultar a API</h2><ol className="muted mt-4 list-decimal space-y-2 pl-5 text-sm"><li>Use o módulo HTTP.</li><li>Adicione <code>Authorization: Bearer nd_live_...</code>.</li><li>Consulte somente o endpoint e escopo necessários.</li><li>Respeite os headers de quota.</li><li>Armazene a chave no cofre/conexão da plataforma, nunca em texto público.</li></ol></article>
      <article className="card p-6"><p className="text-xs font-bold uppercase tracking-wide text-blue-700">n8n</p><h2 className="mt-2 text-xl font-black">Fluxo bidirecional</h2><ol className="muted mt-4 list-decimal space-y-2 pl-5 text-sm"><li>Use Webhook para receber eventos do sistema.</li><li>Valide timestamp + HMAC do corpo bruto.</li><li>Use HTTP Request para consultar/criar dados permitidos pela API v1.</li><li>Persistir <code>X-ND-Delivery</code> impede reprocessamento duplicado.</li><li>Trate HTTP 429 com espera até <code>X-RateLimit-Reset</code>.</li></ol></article>
    </section>

    <section className="mt-8 grid gap-4 lg:grid-cols-2"><article className="card p-6"><h2 className="text-lg font-black">Exemplo de API</h2><pre className="mt-4 overflow-x-auto rounded-xl bg-black/[.04] p-4 text-xs">{apiExample}</pre><p className="muted mt-3 text-xs">Crie uma chave com o menor conjunto de escopos possível. A chave completa aparece uma única vez.</p></article><article className="card p-6"><h2 className="text-lg font-black">Headers de Webhook</h2><pre className="mt-4 overflow-x-auto rounded-xl bg-black/[.04] p-4 text-xs">{webhookHeaders}</pre><p className="muted mt-3 text-xs">Assinatura: HMAC-SHA256(secret, timestamp + "." + raw_body). Responda 2xx somente depois de aceitar o evento para processamento idempotente.</p></article></section>

    <section className="card mt-8 p-6"><h2 className="text-lg font-black">Regras para produção</h2><ul className="muted mt-4 list-disc space-y-2 pl-5 text-sm"><li>Não coloque API keys ou signing secrets em campos públicos, planilhas compartilhadas ou URLs.</li><li>Webhooks podem ser reenviados: sempre implemente idempotência.</li><li>Não interprete uma entrega repetida como um novo evento.</li><li>Use HTTPS e mantenha o endpoint fora de redes privadas/reservadas.</li><li>Comece em homologação com dados de teste antes de ligar automações que alteram sistemas externos.</li></ul></section>
  </main></>;
}
