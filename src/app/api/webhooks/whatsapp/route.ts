import { createHmac, timingSafeEqual } from "node:crypto";
import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export const runtime="nodejs";

function verifySignature(raw:Buffer,header:string|null){
  const secret=process.env.META_WHATSAPP_APP_SECRET;if(!secret||!header?.startsWith("sha256="))return false;
  const expected=`sha256=${createHmac("sha256",secret).update(raw).digest("hex")}`;
  const a=Buffer.from(expected);const b=Buffer.from(header);return a.length===b.length&&timingSafeEqual(a,b);
}
function asDate(timestamp:unknown){const seconds=typeof timestamp==="string"?Number(timestamp):NaN;return Number.isFinite(seconds)?new Date(seconds*1000).toISOString():new Date().toISOString();}
function inboundBody(message:any){if(message?.type==="text")return message?.text?.body||null;if(message?.type==="button")return message?.button?.text||null;if(message?.type==="interactive")return message?.interactive?.button_reply?.title||message?.interactive?.list_reply?.title||null;return null;}

export async function GET(request:NextRequest){const params=request.nextUrl.searchParams;const mode=params.get("hub.mode");const token=params.get("hub.verify_token");const challenge=params.get("hub.challenge");if(mode==="subscribe"&&token&&challenge&&token===process.env.META_WHATSAPP_VERIFY_TOKEN)return new NextResponse(challenge,{status:200});return new NextResponse("Forbidden",{status:403});}

export async function POST(request:NextRequest){
  const raw=Buffer.from(await request.arrayBuffer());if(!verifySignature(raw,request.headers.get("x-hub-signature-256")))return new NextResponse("Invalid signature",{status:401});let payload:any;try{payload=JSON.parse(raw.toString("utf8"));}catch{return new NextResponse("Invalid JSON",{status:400});}const admin=createAdminClient();
  try{for(const entry of Array.isArray(payload?.entry)?payload.entry:[]){for(const change of Array.isArray(entry?.changes)?entry.changes:[]){const value=change?.value||{};const phoneNumberId=String(value?.metadata?.phone_number_id||"");if(!phoneNumberId)continue;const contacts=Array.isArray(value?.contacts)?value.contacts:[];for(const message of Array.isArray(value?.messages)?value.messages:[]){const contact=contacts.find((c:any)=>c?.wa_id===message?.from)||contacts[0];await admin.rpc("service_record_whatsapp_inbound",{p_phone_number_id:phoneNumberId,p_provider_message_id:String(message?.id||""),p_from_phone:String(message?.from||""),p_contact_name:String(contact?.profile?.name||""),p_body:inboundBody(message),p_message_type:String(message?.type||"unknown"),p_received_at:asDate(message?.timestamp)});}for(const status of Array.isArray(value?.statuses)?value.statuses:[]){const state=String(status?.status||"");if(!["sent","delivered","read","failed"].includes(state))continue;const firstError=Array.isArray(status?.errors)?status.errors[0]:null;await admin.rpc("service_update_communication_status",{p_provider:"whatsapp_cloud",p_provider_message_id:String(status?.id||""),p_status:state,p_error_code:firstError?.code?String(firstError.code):null,p_error_message:firstError?.title||firstError?.message||null,p_at:asDate(status?.timestamp)});}}}
  }catch{return new NextResponse("Webhook processing failed",{status:500});}
  return NextResponse.json({received:true});
}
