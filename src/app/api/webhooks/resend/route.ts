import { NextRequest,NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { verifyResendWebhook } from "@/lib/communications/resend-webhook";

export const runtime="nodejs";
export const dynamic="force-dynamic";

type ResendPayload={type?:unknown;created_at?:unknown;data?:{email_id?:unknown;bounce?:{message?:unknown};failed?:{reason?:unknown}}};

export async function POST(request:NextRequest){
  const raw=await request.text();let verified:{id:string};
  try{verified=verifyResendWebhook(raw,{id:request.headers.get("svix-id"),timestamp:request.headers.get("svix-timestamp"),signature:request.headers.get("svix-signature")});}
  catch{return NextResponse.json({error:"invalid_webhook"},{status:400});}
  let payload:ResendPayload;try{payload=JSON.parse(raw) as ResendPayload;}catch{return NextResponse.json({error:"invalid_json"},{status:400});}
  const type=typeof payload.type==="string"?payload.type:"";const emailId=typeof payload.data?.email_id==="string"?payload.data.email_id:"";
  if(!type.startsWith("email.")||!emailId)return NextResponse.json({ok:true,ignored:true});
  const errorMessage=typeof payload.data?.bounce?.message==="string"?payload.data.bounce.message:typeof payload.data?.failed?.reason==="string"?payload.data.failed.reason:null;
  const occurred=typeof payload.created_at==="string"&&!Number.isNaN(Date.parse(payload.created_at))?payload.created_at:new Date().toISOString();
  const admin=createAdminClient();const {data,error}=await admin.rpc("service_record_resend_event",{p_provider_event_id:verified.id,p_event_type:type,p_email_id:emailId,p_occurred_at:occurred,p_error_message:errorMessage});
  if(error){if(error.message.toLowerCase().includes("unsupported resend event"))return NextResponse.json({ok:true,ignored:true});return NextResponse.json({error:"processing_failed"},{status:500});}
  return NextResponse.json({ok:true,processed:Boolean(data)});
}
