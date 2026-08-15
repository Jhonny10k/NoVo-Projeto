import { runPublicApi } from "@/lib/public-api/response";
import { createAdminClient } from "@/lib/supabase/admin";
export const runtime="nodejs";export const dynamic="force-dynamic";

function limitFrom(request:Request){const value=Number(new URL(request.url).searchParams.get("limit")||50);return Number.isFinite(value)?Math.min(Math.max(Math.trunc(value),1),100):50;}

export async function GET(request:Request){return runPublicApi(request,"leads:read","/api/v1/leads",async(context)=>{
  const admin=createAdminClient();const url=new URL(request.url);const limit=limitFrom(request);const after=url.searchParams.get("after");
  let query=admin.from("leads").select("id,name,phone,whatsapp,email,company,source,status,tags,potential_value_cents,interest,last_contact_at,next_contact_at,created_at,updated_at").eq("organization_id",context.organizationId).order("created_at",{ascending:false}).limit(limit);
  if(after&&/^\d{4}-\d{2}-\d{2}T/.test(after))query=query.lt("created_at",after);
  const {data,error}=await query;if(error)throw new Error(error.message);
  const rows=data??[];return{body:{data:rows,next_after:rows.length===limit?rows[rows.length-1]?.created_at??null:null}};
});}

export async function POST(request:Request){return runPublicApi(request,"leads:write","/api/v1/leads",async(context)=>{
  let body:Record<string,unknown>;try{body=await request.json();}catch{return{status:400,body:{error:{code:"invalid_json",message:"JSON inválido."}}};}
  const name=typeof body.name==="string"?body.name.trim().slice(0,160):"";const email=typeof body.email==="string"?body.email.trim().slice(0,254):null;
  const potential=body.potential_value_cents==null?null:Number(body.potential_value_cents);
  if(name.length<2|| (potential!==null&&(!Number.isSafeInteger(potential)||potential<0)))return{status:422,body:{error:{code:"invalid_fields",message:"Revise name e potential_value_cents."}}};
  const admin=createAdminClient();const {data,error}=await admin.rpc("service_create_api_lead",{p_organization_id:context.organizationId,p_name:name,p_phone:typeof body.phone==="string"?body.phone.slice(0,40):null,p_whatsapp:typeof body.whatsapp==="string"?body.whatsapp.slice(0,40):null,p_email:email,p_company:typeof body.company==="string"?body.company.slice(0,160):null,p_interest:typeof body.interest==="string"?body.interest.slice(0,500):null,p_potential_value_cents:potential});
  if(error)return{status:422,body:{error:{code:"invalid_fields",message:"Os dados do lead não passaram na validação."}}};
  return{status:201,body:{data:{id:data}}};
});}
