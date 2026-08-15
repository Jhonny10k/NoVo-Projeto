"use server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireUser } from "@/lib/auth/require-user";
import { encryptIntegrationSecret } from "@/lib/communications/secret-box";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { getFeatureLimit, requireFeature } from "@/lib/plans/entitlements";
import { generatePublicApiKey, parseScopes } from "@/lib/public-api/keys";
import { validateWebhookUrl } from "@/lib/public-api/webhook-security";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { randomBytes } from "node:crypto";

export type SecretState={ok:boolean;secret?:string;error?:string};
function value(fd:FormData,key:string,max=1000){const raw=fd.get(key);return typeof raw==="string"?raw.trim().slice(0,max):"";}
async function ownerContext(feature:"public_api"|"outbound_webhooks"){
  await requireFeature(feature);const user=await requireUser();const organization=await requireCurrentOrganization();
  if(!["owner","admin"].includes(organization.role))return null;return{user,organization,admin:createAdminClient()};
}

export async function createApiKeyAction(_previous:SecretState,fd:FormData):Promise<SecretState>{
  const context=await ownerContext("public_api");if(!context)return{ok:false,error:"Somente proprietário ou administrador pode criar chaves."};
  const name=value(fd,"name",100);const scopes=parseScopes(fd.getAll("scope"));const expires=value(fd,"expires_at",40);
  if(name.length<2||scopes.length===0)return{ok:false,error:"Informe um nome e ao menos um escopo."};
  const limit=(await getFeatureLimit("api_keys"))??3;const {count}=await context.admin.from("api_keys").select("id",{count:"exact",head:true}).eq("organization_id",context.organization.id).eq("status","active");
  if((count??0)>=Math.max(limit,1))return{ok:false,error:`Seu plano permite até ${Math.max(limit,1)} chaves ativas.`};
  const generated=generatePublicApiKey();let expiresAt:string|null=null;
  if(expires){const date=new Date(expires);if(Number.isNaN(date.getTime())||date<=new Date())return{ok:false,error:"A expiração precisa estar no futuro."};expiresAt=date.toISOString();}
  const {data,error}=await context.admin.from("api_keys").insert({organization_id:context.organization.id,name,key_prefix:generated.prefix,secret_hash:generated.hash,scopes,status:"active",expires_at:expiresAt,created_by:context.user.id}).select("id").single();
  if(error||!data)return{ok:false,error:"Não foi possível criar a chave."};
  await context.admin.from("audit_logs").insert({organization_id:context.organization.id,actor_user_id:context.user.id,action:"api_key.created",entity_type:"api_key",entity_id:data.id,metadata:{name,scopes,key_prefix:generated.prefix}});
  revalidatePath("/desenvolvedores");return{ok:true,secret:generated.secret};
}

export async function revokeApiKeyAction(fd:FormData){
  const context=await ownerContext("public_api");if(!context){redirect("/desenvolvedores?erro=permissao");return;}const id=value(fd,"id",80);
  const {data}=await context.admin.from("api_keys").update({status:"revoked",revoked_at:new Date().toISOString(),revoked_by:context.user.id}).eq("id",id).eq("organization_id",context.organization.id).eq("status","active").select("id").maybeSingle();
  if(data)await context.admin.from("audit_logs").insert({organization_id:context.organization.id,actor_user_id:context.user.id,action:"api_key.revoked",entity_type:"api_key",entity_id:id});
  revalidatePath("/desenvolvedores");redirect("/desenvolvedores?status=chave-revogada");
}

export async function createWebhookEndpointAction(_previous:SecretState,fd:FormData):Promise<SecretState>{
  const context=await ownerContext("outbound_webhooks");if(!context)return{ok:false,error:"Somente proprietário ou administrador pode criar endpoints."};
  const name=value(fd,"name",100);const rawUrl=value(fd,"url",1000);const eventTypes=[...new Set(fd.getAll("event_type").filter((x):x is string=>typeof x==="string"))];
  const allowed=new Set(["lead_created","lead_stage_changed","lead_converted_to_customer","quote_created","quote_viewed","quote_response","appointment_created","appointment_status_changed","site_published","subscription_status_changed"]);
  if(name.length<2||eventTypes.length===0||eventTypes.some(e=>!allowed.has(e)))return{ok:false,error:"Informe nome e eventos válidos."};
  let url:string;try{url=await validateWebhookUrl(rawUrl);}catch{return{ok:false,error:"Use uma URL HTTPS pública. Endereços locais/privados são bloqueados."};}
  const limit=(await getFeatureLimit("webhook_endpoints"))??3;const {count}=await context.admin.from("webhook_endpoints").select("id",{count:"exact",head:true}).eq("organization_id",context.organization.id).neq("status","disabled");
  if((count??0)>=Math.max(limit,1))return{ok:false,error:`Seu plano permite até ${Math.max(limit,1)} endpoints.`};
  const secret=`whsec_${randomBytes(32).toString("base64url")}`;const encrypted=encryptIntegrationSecret(secret);
  const {data,error}=await context.admin.from("webhook_endpoints").insert({organization_id:context.organization.id,name,url,event_types:eventTypes,status:"active",signing_secret_prefix:secret.slice(0,16),created_by:context.user.id}).select("id").single();
  if(error||!data)return{ok:false,error:"Não foi possível criar o endpoint."};
  const {error:secretError}=await context.admin.from("webhook_endpoint_secrets").insert({endpoint_id:data.id,ciphertext:encrypted.ciphertext,iv:encrypted.iv,auth_tag:encrypted.authTag});
  if(secretError){await context.admin.from("webhook_endpoints").delete().eq("id",data.id);return{ok:false,error:"Não foi possível proteger o segredo de assinatura."};}
  await context.admin.from("audit_logs").insert({organization_id:context.organization.id,actor_user_id:context.user.id,action:"webhook_endpoint.created",entity_type:"webhook_endpoint",entity_id:data.id,metadata:{name,url,event_types:eventTypes}});
  revalidatePath("/desenvolvedores");return{ok:true,secret};
}

export async function setWebhookEndpointStatusAction(fd:FormData){
  const context=await ownerContext("outbound_webhooks");if(!context){redirect("/desenvolvedores?erro=permissao");return;}const id=value(fd,"id",80);const status=value(fd,"status",20);
  if(!["active","paused","disabled"].includes(status))redirect("/desenvolvedores?erro=webhook");
  await context.admin.from("webhook_endpoints").update({status}).eq("id",id).eq("organization_id",context.organization.id);
  await context.admin.from("audit_logs").insert({organization_id:context.organization.id,actor_user_id:context.user.id,action:"webhook_endpoint.status_changed",entity_type:"webhook_endpoint",entity_id:id,metadata:{status}});
  revalidatePath("/desenvolvedores");redirect("/desenvolvedores?status=webhook-atualizado");
}


export async function retryWebhookDeliveryAction(fd:FormData){
  const context=await ownerContext("outbound_webhooks");
  if(!context){redirect("/desenvolvedores?erro=permissao");return;}
  const id=value(fd,"id",80);
  if(!/^[0-9a-f-]{36}$/i.test(id)){redirect("/desenvolvedores?erro=webhook-retry");return;}
  const supabase=await createClient();
  const {error}=await supabase.rpc("retry_webhook_delivery",{p_organization_id:context.organization.id,p_delivery_id:id});
  if(error){redirect("/desenvolvedores?erro=webhook-retry");return;}
  revalidatePath("/desenvolvedores");
  redirect("/desenvolvedores?status=webhook-reenfileirado");
}
