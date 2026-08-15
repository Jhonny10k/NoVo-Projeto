import "server-only";
import {createAdminClient} from "@/lib/supabase/admin";
import {getAIProvider,isAIConfigured} from "@/lib/ai";
import type {AIGenerateInput} from "@/lib/ai/provider";
import {consumeRateLimit,requestFingerprint} from "@/lib/security/rate-limit";
import {createClient} from "@/lib/supabase/server";

type Resource="assistant"|"lead_response"|"copy"|"quote"|"insights";
function estimateCostMicros(inputTokens:number,outputTokens:number){const input=Number(process.env.OPENAI_INPUT_PRICE_PER_1M_USD);const output=Number(process.env.OPENAI_OUTPUT_PRICE_PER_1M_USD);if(!Number.isFinite(input)||input<0||!Number.isFinite(output)||output<0)return null;return Math.round(inputTokens*input+outputTokens*output);}
function safeErrorCode(error:unknown){const value=error instanceof Error?error.message:"AI_REQUEST_FAILED";return value.replace(/[^A-Z0-9_\-]/gi,"_").slice(0,100);}
export async function runOrganizationAI(input:{organizationId:string;resource:Resource;instructions:string;prompt:string;maxOutputTokens?:number}){
  if(!isAIConfigured())throw new Error("AI_PROVIDER_NOT_CONFIGURED");
  const fingerprint=await requestFingerprint(`ai:${input.organizationId}:${input.resource}`);const rate=await consumeRateLimit({scope:"ai_generation",identifierHash:fingerprint,limit:30,windowSeconds:3600});if(!rate.allowed)throw new Error("AI_RATE_LIMIT");
  const supabase=await createClient();const {data:usageId,error:beginError}=await supabase.rpc("begin_ai_usage",{p_organization_id:input.organizationId,p_resource:input.resource});if(beginError||!usageId)throw new Error(beginError?.message||"AI_USAGE_RESERVATION_FAILED");
  const admin=createAdminClient();
  try{
    const provider=getAIProvider();const result=await provider.generate({instructions:input.instructions.slice(0,8000),input:input.prompt.slice(0,20000),maxOutputTokens:input.maxOutputTokens});
    await admin.from("ai_usage").update({status:"succeeded",provider:result.provider,model:result.model,provider_request_id:result.providerRequestId,input_tokens:result.inputTokens,output_tokens:result.outputTokens,total_tokens:result.totalTokens,estimated_cost_usd_micros:estimateCostMicros(result.inputTokens,result.outputTokens),completed_at:new Date().toISOString()}).eq("id",usageId);
    return result.text;
  }catch(error){await admin.from("ai_usage").update({status:"failed",error_code:safeErrorCode(error),completed_at:new Date().toISOString()}).eq("id",usageId);throw error;}
}
