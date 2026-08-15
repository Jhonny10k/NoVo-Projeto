import "server-only";
import { getPublicAppUrl } from "@/lib/env";

type Payload=Record<string,unknown>;
export type SystemEmailTemplate={subject:string;text:string};

function text(value:unknown,max=160){return typeof value==="string"?value.trim().slice(0,max):"";}
function org(payload:Payload){return text(payload.organization_name)||"Sua empresa";}

export function renderSystemEmail(kind:string,payload:Payload):SystemEmailTemplate{
  const appUrl=getPublicAppUrl().replace(/\/$/,"");
  if(kind==="welcome")return{
    subject:`Bem-vindo à plataforma — ${org(payload)}`,
    text:`Bem-vindo! Vamos colocar ${org(payload)} no digital.\n\nSeu espaço já foi criado. Agora complete as informações da empresa, revise seu site e publique quando estiver pronto.\n\nAbrir painel: ${appUrl}/dashboard\n\nSe você não reconhece este cadastro, entre em contato com o suporte.`
  };
  if(kind==="new_lead"){
    const name=text(payload.lead_name)||"Novo contato";const source=text(payload.source)||"não informada";const interest=text(payload.interest,240);
    return{subject:`Novo lead: ${name}`,text:`${org(payload)} recebeu um novo lead.\n\nNome: ${name}\nOrigem: ${source}${interest?`\nInteresse: ${interest}`:""}\n\nAbra o CRM para atender: ${appUrl}/crm`};
  }
  if(kind.startsWith("subscription_")){
    const status=kind.slice("subscription_".length);const plan=text(payload.plan_name)||"plano atual";
    const labels:Record<string,string>={active:"ativa",past_due:"com pagamento pendente",suspended:"suspensa",canceled:"cancelada"};
    const label=labels[status]||status;
    return{subject:`Assinatura ${label} — ${org(payload)}`,text:`A assinatura de ${org(payload)} está ${label}.\nPlano: ${plan}.\n\nConfira os detalhes em: ${appUrl}/assinatura\n\nEste e-mail reflete o status registrado pelo provedor de cobrança; ele não é uma promessa de pagamento futuro.`};
  }
  throw new Error("OUTBOX_EMAIL_KIND_UNSUPPORTED");
}
