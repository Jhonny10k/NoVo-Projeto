import "server-only";
import { randomUUID } from "node:crypto";
import { createAdminClient } from "@/lib/supabase/admin";
import { hashPublicApiKey, type PublicApiScope } from "@/lib/public-api/keys";

export type ApiContext={organizationId:string;apiKeyId:string;keyPrefix:string;remaining:number;limit:number;resetAt:string;requestId:string};

type ConsumeResult={organization_id:string;api_key_id:string;key_prefix:string;remaining:number;limit:number;reset_at:string};

export class PublicApiError extends Error{
  constructor(public status:number,public code:string,message:string){super(message);}
}

export async function authenticatePublicApi(request:Request,scope:PublicApiScope):Promise<ApiContext>{
  const header=request.headers.get("authorization")||"";
  const match=/^Bearer\s+(nd_live_[A-Za-z0-9_-]{20,120})$/i.exec(header.trim());
  if(!match)throw new PublicApiError(401,"invalid_api_key","Use Authorization: Bearer <api_key>.");
  let hash:string;
  try{hash=hashPublicApiKey(match[1]);}catch{throw new PublicApiError(503,"api_not_configured","API pública ainda não foi configurada no servidor.");}
  const admin=createAdminClient();
  const {data,error}=await admin.rpc("service_consume_public_api_key",{p_secret_hash:hash,p_required_scope:scope});
  if(error){
    const message=String(error.message||"").toLowerCase();
    if(message.includes("rate limit"))throw new PublicApiError(429,"rate_limit_exceeded","Limite horário da API excedido.");
    if(message.includes("scope"))throw new PublicApiError(403,"insufficient_scope","A chave não possui o escopo necessário.");
    if(message.includes("feature"))throw new PublicApiError(403,"feature_unavailable","O plano não possui API pública ativa.");
    throw new PublicApiError(401,"invalid_api_key","Chave inválida, revogada ou expirada.");
  }
  const value=data as ConsumeResult;
  return {organizationId:value.organization_id,apiKeyId:value.api_key_id,keyPrefix:value.key_prefix,remaining:Number(value.remaining),limit:Number(value.limit),resetAt:value.reset_at,requestId:request.headers.get("x-request-id")?.slice(0,100)||randomUUID()};
}

export async function logPublicApiRequest(context:ApiContext,input:{scope:string;method:string;route:string;status:number;durationMs:number}){
  try{const admin=createAdminClient();await admin.from("api_request_logs").insert({organization_id:context.organizationId,api_key_id:context.apiKeyId,scope:input.scope,method:input.method.slice(0,12),route:input.route.slice(0,240),response_status:input.status,duration_ms:Math.max(0,Math.trunc(input.durationMs)),request_id:context.requestId});}catch{}
}

export function apiHeaders(context:ApiContext){
  return {"X-Request-Id":context.requestId,"X-RateLimit-Limit":String(context.limit),"X-RateLimit-Remaining":String(context.remaining),"X-RateLimit-Reset":context.resetAt,"Cache-Control":"private, no-store"};
}
