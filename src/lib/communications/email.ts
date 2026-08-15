import "server-only";

export function isTransactionalEmailConfigured(){return Boolean(process.env.RESEND_API_KEY&&process.env.RESEND_FROM_EMAIL);}
export function isResendWebhookConfigured(){return Boolean(process.env.RESEND_WEBHOOK_SECRET);}

function env(){
  const apiKey=process.env.RESEND_API_KEY;const fromEmail=process.env.RESEND_FROM_EMAIL;
  if(!apiKey||!fromEmail)throw new Error("EMAIL_PROVIDER_NOT_CONFIGURED");
  return{apiKey,fromEmail,fromName:(process.env.RESEND_FROM_NAME||"Atendimento").trim().slice(0,100)};
}

export type SendEmailInput={to:string;subject:string;text:string;replyTo?:string|null;idempotencyKey:string;fromName?:string|null};
export async function sendTransactionalEmail(input:SendEmailInput){
  const cfg=env();const controller=new AbortController();const timeout=setTimeout(()=>controller.abort(),12000);
  try{
    const response=await fetch("https://api.resend.com/emails",{method:"POST",signal:controller.signal,headers:{Authorization:`Bearer ${cfg.apiKey}`,"Content-Type":"application/json","Idempotency-Key":input.idempotencyKey},body:JSON.stringify({from:`${(input.fromName||cfg.fromName).replace(/[<>\r\n]/g,"")} <${cfg.fromEmail}>`,to:[input.to],subject:input.subject,text:input.text,...(input.replyTo?{reply_to:input.replyTo}:{})})});
    const body=await response.json().catch(()=>({}));
    if(!response.ok||typeof body?.id!=="string")throw new Error(`EMAIL_PROVIDER_ERROR_${response.status}`);
    return{id:body.id as string};
  }finally{clearTimeout(timeout);}
}
