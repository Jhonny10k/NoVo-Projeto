import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";
import { decryptIntegrationSecret } from "@/lib/communications/secret-box";

export type WhatsAppConnection={id:string;organization_id:string;status:string;config:{phone_number_id?:string;waba_id?:string;display_phone_number?:string;verified_name?:string}};
function graphVersion(){const value=(process.env.META_GRAPH_API_VERSION||"").trim();if(!/^v\d+\.\d+$/.test(value))throw new Error("META_GRAPH_API_VERSION_NOT_CONFIGURED");return value;}
function normalizePhone(value:string){const digits=value.replace(/\D/g,"");if(digits.length<8||digits.length>15)throw new Error("INVALID_WHATSAPP_PHONE");return digits;}

export function isWhatsAppWebhookConfigured(){return Boolean(process.env.META_WHATSAPP_APP_SECRET&&process.env.META_WHATSAPP_VERIFY_TOKEN);}

export async function getWhatsAppConnection(organizationId:string,requireActive=true){
  const admin=createAdminClient();
  const {data:connection,error}=await admin.from("integration_connections").select("id,organization_id,status,config").eq("organization_id",organizationId).eq("provider","whatsapp_cloud").maybeSingle();
  if(error||!connection)throw new Error("WHATSAPP_NOT_CONNECTED");
  if(requireActive&&connection.status!=="active")throw new Error("WHATSAPP_NOT_VERIFIED");
  const {data:secret,error:secretError}=await admin.from("integration_secrets").select("ciphertext,iv,auth_tag").eq("connection_id",connection.id).maybeSingle();
  if(secretError||!secret)throw new Error("WHATSAPP_SECRET_MISSING");
  const accessToken=decryptIntegrationSecret({ciphertext:secret.ciphertext,iv:secret.iv,authTag:secret.auth_tag});
  return{connection:connection as WhatsAppConnection,accessToken};
}

async function metaRequest(path:string,token:string,init?:RequestInit){
  const controller=new AbortController();const timeout=setTimeout(()=>controller.abort(),12000);
  try{const response=await fetch(`https://graph.facebook.com/${graphVersion()}/${path}`,{...init,signal:controller.signal,headers:{Authorization:`Bearer ${token}`,...(init?.body?{"Content-Type":"application/json"}:{}),...(init?.headers||{})}});const body=await response.json().catch(()=>({}));if(!response.ok)throw new Error(`WHATSAPP_PROVIDER_ERROR_${response.status}:${String(body?.error?.message||"").slice(0,200)}`);return body;}finally{clearTimeout(timeout);}
}

export async function verifyWhatsAppConnection(organizationId:string){
  const {connection,accessToken}=await getWhatsAppConnection(organizationId,false);const phoneId=connection.config.phone_number_id;
  if(!phoneId||!/^[0-9]{5,40}$/.test(phoneId))throw new Error("INVALID_PHONE_NUMBER_ID");
  const data=await metaRequest(`${phoneId}?fields=display_phone_number,verified_name,quality_rating`,accessToken);
  return{displayPhoneNumber:typeof data?.display_phone_number==="string"?data.display_phone_number:null,verifiedName:typeof data?.verified_name==="string"?data.verified_name:null,qualityRating:typeof data?.quality_rating==="string"?data.quality_rating:null};
}

async function send(organizationId:string,to:string,payload:Record<string,unknown>){
  const {connection,accessToken}=await getWhatsAppConnection(organizationId,true);const phoneId=connection.config.phone_number_id;if(!phoneId)throw new Error("INVALID_PHONE_NUMBER_ID");
  const data=await metaRequest(`${phoneId}/messages`,accessToken,{method:"POST",body:JSON.stringify({messaging_product:"whatsapp",recipient_type:"individual",to:normalizePhone(to),...payload})});
  const id=data?.messages?.[0]?.id;if(typeof id!=="string")throw new Error("WHATSAPP_PROVIDER_INVALID_RESPONSE");return{id};
}

export async function sendWhatsAppText(organizationId:string,to:string,body:string){return send(organizationId,to,{type:"text",text:{preview_url:false,body}});}
export async function sendWhatsAppTemplate(organizationId:string,to:string,name:string,language:string,parameters:string[]){
  const components=parameters.length?[{type:"body",parameters:parameters.map(text=>({type:"text",text}))}]:undefined;
  return send(organizationId,to,{type:"template",template:{name,language:{code:language},...(components?{components}:{})}});
}
export { normalizePhone };
