import "server-only";
import { randomUUID } from "node:crypto";
import { createAdminClient } from "@/lib/supabase/admin";
import { sendTransactionalEmail } from "@/lib/communications/email";
import { renderSystemEmail } from "@/lib/outbox/email-templates";
import { deleteGoogleCalendarAppointment,upsertGoogleCalendarAppointment } from "@/lib/integrations/google-calendar";
import { deliverClientWebhook } from "@/lib/public-api/client-webhook";

type OutboxJob={
  id:string;organization_id:string;provider:string;kind:string;recipient_user_id:string|null;recipient:string|null;
  entity_type:string|null;entity_id:string|null;payload:Record<string,unknown>;attempts:number;max_attempts:number;
};

async function resolveRecipient(admin:ReturnType<typeof createAdminClient>,job:OutboxJob){
  if(job.recipient?.includes("@"))return job.recipient.trim().toLowerCase();
  if(!job.recipient_user_id)throw new Error("OUTBOX_RECIPIENT_MISSING");
  const {data,error}=await admin.auth.admin.getUserById(job.recipient_user_id);
  if(error||!data.user?.email)throw new Error("OUTBOX_USER_EMAIL_NOT_FOUND");
  return data.user.email;
}

async function ensureMessage(admin:ReturnType<typeof createAdminClient>,job:OutboxJob,to:string,subject:string,body:string){
  const {error}=await admin.from("communication_messages").upsert({
    id:job.id,organization_id:job.organization_id,channel:"email",direction:"outbound",provider:"resend",
    recipient:to,subject,body,status:"queued",
    ...(job.entity_type==="lead"&&job.entity_id?{lead_id:job.entity_id}:{}),
    ...(job.entity_type==="customer"&&job.entity_id?{customer_id:job.entity_id}:{})
  },{onConflict:"id",ignoreDuplicates:true});
  if(error)throw new Error(`OUTBOX_MESSAGE_LOG_${error.message}`);
}

async function processEmail(admin:ReturnType<typeof createAdminClient>,job:OutboxJob){
  const to=await resolveRecipient(admin,job);const template=renderSystemEmail(job.kind,job.payload||{});
  const {data:organization}=await admin.from("organizations").select("name,email").eq("id",job.organization_id).maybeSingle();
  await ensureMessage(admin,job,to,template.subject,template.text);
  const sent=await sendTransactionalEmail({
    to,subject:template.subject,text:template.text,replyTo:organization?.email||null,
    idempotencyKey:`outbox-${job.id}`,fromName:organization?.name||null
  });
  await admin.from("communication_messages").update({provider_message_id:sent.id,status:"sent",sent_at:new Date().toISOString(),error_message:null}).eq("id",job.id);
  return sent.id;
}

export async function processExternalOutbox(limit=20){
  const admin=createAdminClient();const workerId=`next-${randomUUID()}`;
  const {data,error}=await admin.rpc("service_claim_external_outbox",{p_worker_id:workerId,p_limit:Math.min(Math.max(limit,1),50)});
  if(error)throw new Error(error.message);
  const jobs=(data||[]) as OutboxJob[];const results:{id:string;status:string}[]=[];
  for(const job of jobs){
    try{
      let providerId:string;
      if(job.provider==="resend")providerId=await processEmail(admin,job);
      else if(job.provider==="google_calendar"&&job.entity_id){
        const result=job.kind==="calendar_delete_appointment"
          ?await deleteGoogleCalendarAppointment(job.organization_id,job.entity_id)
          :await upsertGoogleCalendarAppointment(job.organization_id,job.entity_id);
        providerId=result.id;
      }else if(job.provider==="client_webhook")providerId=await deliverClientWebhook(job);
      else throw new Error(`OUTBOX_PROVIDER_UNSUPPORTED_${job.provider}`);
      const {error:completeError}=await admin.rpc("service_complete_external_outbox",{p_job_id:job.id,p_worker_id:workerId,p_provider_message_id:providerId});
      if(completeError)throw new Error(completeError.message);
      results.push({id:job.id,status:"sent"});
    }catch(error){
      const message=(error instanceof Error?error.message:"outbox error").slice(0,1500);
      const {data:failureStatus}=await admin.rpc("service_fail_external_outbox",{p_job_id:job.id,p_worker_id:workerId,p_error:message});
      if(failureStatus==="dead_letter"){
        if(job.provider==="resend")await admin.from("communication_messages").update({status:"failed",error_message:message}).eq("id",job.id);
        if(job.provider==="google_calendar"&&job.entity_id)await admin.from("appointment_external_events").update({status:"error",last_error:message,last_synced_at:new Date().toISOString()}).eq("organization_id",job.organization_id).eq("appointment_id",job.entity_id).eq("provider","google_calendar");
        if(job.provider==="client_webhook"&&job.entity_id){
          await admin.from("webhook_deliveries").update({status:"failed",attempts:job.attempts,last_error:message}).eq("id",job.entity_id).eq("organization_id",job.organization_id);
          const endpointId=typeof job.payload?.endpoint_id==="string"?job.payload.endpoint_id:null;if(endpointId)await admin.from("webhook_endpoints").update({last_failure_at:new Date().toISOString(),last_error:message}).eq("id",endpointId).eq("organization_id",job.organization_id);
        }
      }
      if(job.provider==="client_webhook"&&job.entity_id&&failureStatus!=="dead_letter")await admin.from("webhook_deliveries").update({status:"retry",attempts:job.attempts,last_error:message}).eq("id",job.entity_id).eq("organization_id",job.organization_id);
      results.push({id:job.id,status:String(failureStatus||"retry")});
    }
  }
  return{workerId,claimed:jobs.length,results};
}
