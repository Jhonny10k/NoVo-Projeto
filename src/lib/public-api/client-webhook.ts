import "server-only";
import { createHmac } from "node:crypto";
import { decryptIntegrationSecret } from "@/lib/communications/secret-box";
import { validateWebhookUrl } from "@/lib/public-api/webhook-security";
import { createAdminClient } from "@/lib/supabase/admin";

type WebhookJob={id:string;organization_id:string;kind:string;entity_id:string|null;payload:Record<string,unknown>;attempts:number};

export async function deliverClientWebhook(job:WebhookJob){
  const endpointId=typeof job.payload.endpoint_id==="string"?job.payload.endpoint_id:"";const deliveryId=typeof job.payload.delivery_id==="string"?job.payload.delivery_id:job.entity_id||"";
  if(!endpointId||!deliveryId)throw new Error("CLIENT_WEBHOOK_PAYLOAD_INVALID");
  const admin=createAdminClient();
  const [{data:endpoint,error:endpointError},{data:secret,error:secretError}]=await Promise.all([
    admin.from("webhook_endpoints").select("id,url,status").eq("id",endpointId).eq("organization_id",job.organization_id).maybeSingle(),
    admin.from("webhook_endpoint_secrets").select("ciphertext,iv,auth_tag").eq("endpoint_id",endpointId).maybeSingle()
  ]);
  if(endpointError||!endpoint||endpoint.status!=="active")throw new Error("CLIENT_WEBHOOK_ENDPOINT_INACTIVE");
  if(secretError||!secret)throw new Error("CLIENT_WEBHOOK_SECRET_MISSING");
  const url=await validateWebhookUrl(endpoint.url);
  const signingSecret=decryptIntegrationSecret({ciphertext:secret.ciphertext,iv:secret.iv,authTag:secret.auth_tag});
  const event={
    id:deliveryId,type:job.kind,created_at:typeof job.payload.occurred_at==="string"?job.payload.occurred_at:new Date().toISOString(),
    data:{event_id:job.payload.event_id??null,entity_type:job.payload.entity_type??null,entity_id:job.payload.entity_id??null,metadata:job.payload.metadata??{}}
  };
  const body=JSON.stringify(event);const timestamp=String(Math.floor(Date.now()/1000));
  const signature=createHmac("sha256",signingSecret).update(`${timestamp}.${body}`,"utf8").digest("hex");
  await admin.from("webhook_deliveries").update({status:"processing",attempts:job.attempts,last_error:null}).eq("id",deliveryId).eq("organization_id",job.organization_id);
  const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),10000);
  try{
    const response=await fetch(url,{method:"POST",headers:{"content-type":"application/json","user-agent":"NegocioDigital-Webhooks/1.0","x-nd-event":job.kind,"x-nd-delivery":deliveryId,"x-nd-timestamp":timestamp,"x-nd-signature":`v1=${signature}`,"idempotency-key":deliveryId},body,signal:controller.signal,redirect:"error",cache:"no-store"});
    if(!response.ok){const detail=(await response.text()).slice(0,300);await admin.from("webhook_deliveries").update({response_status:response.status}).eq("id",deliveryId);throw new Error(`CLIENT_WEBHOOK_HTTP_${response.status}${detail?`_${detail}`:""}`);}
    await Promise.all([
      admin.from("webhook_deliveries").update({status:"delivered",attempts:job.attempts,response_status:response.status,delivered_at:new Date().toISOString(),last_error:null}).eq("id",deliveryId),
      admin.from("webhook_endpoints").update({last_success_at:new Date().toISOString(),last_error:null}).eq("id",endpointId)
    ]);
    return response.headers.get("x-request-id")||deliveryId;
  }finally{clearTimeout(timer);}
}
