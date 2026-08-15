export type CommunicationTemplate={code:string;label:string;subject?:string;body:string};

type LeadTemplateContext={name:string;interest?:string|null};

function safeName(value:string){const name=value.trim().slice(0,120);return name||"cliente";}
function safeInterest(value?:string|null){return (value||"").trim().slice(0,240);}

export function leadCommunicationTemplates(context:LeadTemplateContext):CommunicationTemplate[]{
  const name=safeName(context.name);const interest=safeInterest(context.interest);const topic=interest?` sobre ${interest}`:"";
  return[
    {code:"first_contact",label:"Primeiro contato",subject:"Recebemos seu contato",body:`Olá, ${name}! Tudo bem?\n\nRecebemos seu contato${topic}. Posso te ajudar com mais algumas informações?`},
    {code:"quote_follow_up",label:"Follow-up do orçamento",subject:"Conseguiu verificar seu orçamento?",body:`Olá, ${name}!\n\nConseguiu verificar o orçamento que enviamos? Se tiver qualquer dúvida ou precisar de algum ajuste, posso ajudar.`},
    {code:"availability",label:"Disponibilidade para atendimento",subject:"Podemos avançar com seu atendimento?",body:`Olá, ${name}!\n\nEstou entrando em contato para confirmar se podemos avançar com seu atendimento. Se preferir, me diga o melhor horário para conversarmos.`}
  ];
}
