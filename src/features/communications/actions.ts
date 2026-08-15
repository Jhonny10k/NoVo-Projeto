"use server";
import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireUser } from "@/lib/auth/require-user";
import { sendTransactionalEmail } from "@/lib/communications/email";
import { normalizePhone, sendWhatsAppTemplate, sendWhatsAppText } from "@/lib/communications/whatsapp";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { requireFeature } from "@/lib/plans/entitlements";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

function field(fd:FormData,key:string,max=1000){const value=fd.get(key);return typeof value==="string"?value.trim().slice(0,max):"";}
function canSend(role:string){return role!=="viewer";}
async function baseContext(feature:"email_transactional"|"whatsapp_official"){
  await requireFeature(feature);const user=await requireUser();const organization=await requireCurrentOrganization();if(!canSend(organization.role))redirect("/crm?erro=permissao");return{user,organization,supabase:await createClient(),admin:createAdminClient()};
}
async function loadLead(id:string,organizationId:string,supabase:Awaited<ReturnType<typeof createClient>>){const {data}=await supabase.from("leads").select("id,name,email,phone,whatsapp").eq("organization_id",organizationId).eq("id",id).maybeSingle();return data;}

export async function sendLeadEmailAction(fd:FormData){
  const {user,organization,supabase,admin}=await baseContext("email_transactional");const leadId=field(fd,"lead_id",80);const subject=field(fd,"subject",200);const body=field(fd,"body",10000);if(!leadId||subject.length<2||body.length<2)redirect(`/crm/${leadId}?erro=email_campos`);
  const lead=await loadLead(leadId,organization.id,supabase);if(!lead?.email)redirect(`/crm/${leadId}?erro=email_indisponivel`);
  const {data:org}=await supabase.from("organizations").select("email,name").eq("id",organization.id).single();const messageId=randomUUID();
  const {error:queuedError}=await admin.from("communication_messages").insert({id:messageId,organization_id:organization.id,channel:"email",direction:"outbound",provider:"resend",lead_id:leadId,recipient:lead.email,subject,body,status:"queued",created_by:user.id});if(queuedError)redirect(`/crm/${leadId}?erro=email_log`);
  try{const sent=await sendTransactionalEmail({to:lead.email,subject,text:body,replyTo:org?.email||null,idempotencyKey:`email-${messageId}`,fromName:org?.name||organization.name});await admin.from("communication_messages").update({provider_message_id:sent.id,status:"sent",sent_at:new Date().toISOString()}).eq("id",messageId);await admin.from("events").insert({organization_id:organization.id,actor_user_id:user.id,entity_type:"lead",entity_id:leadId,event_type:"email_sent",metadata:{message_id:messageId,subject}});}
  catch(error){await admin.from("communication_messages").update({status:"failed",error_message:(error instanceof Error?error.message:"email failed").slice(0,1000)}).eq("id",messageId);redirect(`/crm/${leadId}?erro=email_envio`);}
  revalidatePath(`/crm/${leadId}`);redirect(`/crm/${leadId}?status=email_enviado`);
}

export async function sendLeadWhatsAppTextAction(fd:FormData){
  const {user,organization,supabase,admin}=await baseContext("whatsapp_official");const leadId=field(fd,"lead_id",80);const body=field(fd,"body",4096);if(!leadId||body.length<1)redirect(`/crm/${leadId}?erro=whatsapp_campos`);const lead=await loadLead(leadId,organization.id,supabase);const target=lead?.whatsapp||lead?.phone;if(!target)redirect(`/crm/${leadId}?erro=whatsapp_indisponivel`);let phone:string;try{phone=normalizePhone(target);}catch{redirect(`/crm/${leadId}?erro=whatsapp_indisponivel`);throw new Error("redirect");}
  const cutoff=new Date(Date.now()-24*60*60*1000).toISOString();const {data:inbound}=await supabase.from("communication_messages").select("id").eq("organization_id",organization.id).eq("channel","whatsapp").eq("direction","inbound").eq("sender",phone).gte("received_at",cutoff).limit(1);
  if(!inbound?.length)redirect(`/crm/${leadId}?erro=whatsapp_janela`);
  const messageId=randomUUID();const {error:queuedError}=await admin.from("communication_messages").insert({id:messageId,organization_id:organization.id,channel:"whatsapp",direction:"outbound",provider:"whatsapp_cloud",lead_id:leadId,recipient:phone,body,message_type:"text",status:"queued",created_by:user.id});if(queuedError)redirect(`/crm/${leadId}?erro=whatsapp_log`);
  try{const sent=await sendWhatsAppText(organization.id,phone,body);await admin.from("communication_messages").update({provider_message_id:sent.id,status:"sent",sent_at:new Date().toISOString()}).eq("id",messageId);await admin.from("events").insert({organization_id:organization.id,actor_user_id:user.id,entity_type:"lead",entity_id:leadId,event_type:"whatsapp_message_sent",metadata:{message_id:messageId,message_type:"text"}});}
  catch(error){await admin.from("communication_messages").update({status:"failed",error_message:(error instanceof Error?error.message:"whatsapp failed").slice(0,1000)}).eq("id",messageId);redirect(`/crm/${leadId}?erro=whatsapp_envio`);}
  revalidatePath(`/crm/${leadId}`);redirect(`/crm/${leadId}?status=whatsapp_enviado`);
}

export async function sendLeadWhatsAppTemplateAction(fd:FormData){
  const {user,organization,supabase,admin}=await baseContext("whatsapp_official");const leadId=field(fd,"lead_id",80);const template=field(fd,"template_name",512);const language=field(fd,"template_language",35)||"pt_BR";const rawParams=field(fd,"template_parameters",5000);if(!leadId||!/^[a-z0-9_]{1,512}$/.test(template)||!/^[A-Za-z_\-]{2,35}$/.test(language))redirect(`/crm/${leadId}?erro=whatsapp_template`);const parameters=rawParams.split(/\r?\n/).map(v=>v.trim()).filter(Boolean).slice(0,20).map(v=>v.slice(0,1000));const lead=await loadLead(leadId,organization.id,supabase);const target=lead?.whatsapp||lead?.phone;if(!target)redirect(`/crm/${leadId}?erro=whatsapp_indisponivel`);let phone:string;try{phone=normalizePhone(target);}catch{redirect(`/crm/${leadId}?erro=whatsapp_indisponivel`);throw new Error("redirect");}
  const messageId=randomUUID();const {error:queuedError}=await admin.from("communication_messages").insert({id:messageId,organization_id:organization.id,channel:"whatsapp",direction:"outbound",provider:"whatsapp_cloud",lead_id:leadId,recipient:phone,body:parameters.length?parameters.join("\n"):null,message_type:"template",template_name:template,status:"queued",created_by:user.id});if(queuedError)redirect(`/crm/${leadId}?erro=whatsapp_log`);
  try{const sent=await sendWhatsAppTemplate(organization.id,phone,template,language,parameters);await admin.from("communication_messages").update({provider_message_id:sent.id,status:"sent",sent_at:new Date().toISOString()}).eq("id",messageId);await admin.from("events").insert({organization_id:organization.id,actor_user_id:user.id,entity_type:"lead",entity_id:leadId,event_type:"whatsapp_message_sent",metadata:{message_id:messageId,message_type:"template",template_name:template}});}
  catch(error){await admin.from("communication_messages").update({status:"failed",error_message:(error instanceof Error?error.message:"whatsapp failed").slice(0,1000)}).eq("id",messageId);redirect(`/crm/${leadId}?erro=whatsapp_envio`);}
  revalidatePath(`/crm/${leadId}`);redirect(`/crm/${leadId}?status=whatsapp_enviado`);
}

export async function sendQuoteEmailAction(fd:FormData){
  await requireFeature("quotes");const {user,organization,supabase,admin}=await baseContext("email_transactional");const quoteId=field(fd,"quote_id",80);if(!quoteId)redirect("/orcamentos?erro=campos");
  const {data:quote}=await supabase.from("quotes").select("id,status,public_token,total_cents,valid_until,lead_id,customer_id").eq("organization_id",organization.id).eq("id",quoteId).maybeSingle();if(!quote)redirect(`/orcamentos/${quoteId}?erro=email_indisponivel`);
  let recipient:{name:string;email:string|null}|null=null;if(quote.lead_id){const {data}=await supabase.from("leads").select("name,email").eq("organization_id",organization.id).eq("id",quote.lead_id).maybeSingle();recipient=data;}else if(quote.customer_id){const {data}=await supabase.from("customers").select("name,email").eq("organization_id",organization.id).eq("id",quote.customer_id).maybeSingle();recipient=data;}if(!recipient?.email){redirect(`/orcamentos/${quoteId}?erro=email_indisponivel`);throw new Error("redirect");}
  const recipientName=recipient.name;const recipientEmail=recipient.email;
  if(quote.status==="draft"){const {error}=await supabase.rpc("publish_quote_link",{p_organization_id:organization.id,p_quote_id:quoteId});if(error)redirect(`/orcamentos/${quoteId}?erro=publicar`);}
  const {data:org}=await supabase.from("organizations").select("email,name").eq("id",organization.id).single();const appUrl=(process.env.NEXT_PUBLIC_APP_URL||"http://localhost:3000").replace(/\/$/,"");const link=`${appUrl}/orcamento/${quote.public_token}`;const total=new Intl.NumberFormat("pt-BR",{style:"currency",currency:"BRL"}).format(Number(quote.total_cents||0)/100);const message=`Olá, ${recipientName}!\n\nSeu orçamento da ${org?.name||organization.name} está pronto.\nTotal: ${total}${quote.valid_until?`\nValidade: ${new Date(`${quote.valid_until}T12:00:00Z`).toLocaleDateString("pt-BR")}`:""}\n\nAcesse, revise e responda pelo link:\n${link}\n\nSe precisar de alguma alteração, use a opção disponível no próprio orçamento.`;const messageId=randomUUID();
  const {error:queuedError}=await admin.from("communication_messages").insert({id:messageId,organization_id:organization.id,channel:"email",direction:"outbound",provider:"resend",lead_id:quote.lead_id,customer_id:quote.customer_id,recipient:recipientEmail,subject:`Seu orçamento — ${org?.name||organization.name}`,body:message,status:"queued",created_by:user.id});if(queuedError)redirect(`/orcamentos/${quoteId}?erro=email_log`);
  try{const sent=await sendTransactionalEmail({to:recipientEmail,subject:`Seu orçamento — ${org?.name||organization.name}`,text:message,replyTo:org?.email||null,idempotencyKey:`quote-email-${messageId}`,fromName:org?.name||organization.name});await admin.from("communication_messages").update({provider_message_id:sent.id,status:"sent",sent_at:new Date().toISOString()}).eq("id",messageId);await admin.from("events").insert({organization_id:organization.id,actor_user_id:user.id,entity_type:"quote",entity_id:quoteId,event_type:"quote_email_sent",metadata:{message_id:messageId}});}catch(error){await admin.from("communication_messages").update({status:"failed",error_message:(error instanceof Error?error.message:"email failed").slice(0,1000)}).eq("id",messageId);redirect(`/orcamentos/${quoteId}?erro=email_envio`);}
  revalidatePath(`/orcamentos/${quoteId}`);redirect(`/orcamentos/${quoteId}?status=email_enviado`);
}
