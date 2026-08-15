"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { requireFeature } from "@/lib/plans/entitlements";
import { consumeRateLimit, requestFingerprint } from "@/lib/security/rate-limit";
import { createClient } from "@/lib/supabase/server";

function field(formData: FormData,key:string,max=500){const v=formData.get(key);return typeof v==="string"?v.trim().slice(0,max):"";}
function validTime(v:string){return /^([01]\d|2[0-3]):[0-5]\d$/.test(v);}

export async function saveBookingSettingsAction(formData:FormData){
  await requireFeature("appointments"); const organization=await requireCurrentOrganization(); if(!["owner","admin"].includes(organization.role)) redirect("/agenda?erro=permissao");
  const slot=Number(field(formData,"slot_duration_minutes",4)); const buffer=Number(field(formData,"buffer_minutes",4)); const availability:Record<string,string[][]>={};
  for(let day=1;day<=7;day++){if(formData.get(`day_${day}_enabled`)!=="on") continue; const start=field(formData,`day_${day}_start`,5); const end=field(formData,`day_${day}_end`,5); if(!validTime(start)||!validTime(end)||start>=end) redirect("/agenda?erro=horario"); availability[String(day)]=[[start,end]];}
  if(!Number.isInteger(slot)||slot<15||slot>480||!Number.isInteger(buffer)||buffer<0||buffer>180) redirect("/agenda?erro=config");
  const supabase=await createClient(); const {error}=await supabase.rpc("save_booking_settings",{p_organization_id:organization.id,p_enabled:formData.get("enabled")==="on",p_slot_duration_minutes:slot,p_buffer_minutes:buffer,p_availability:availability});
  if(error) redirect("/agenda?erro=salvar"); revalidatePath("/agenda"); revalidatePath(`/agendar/${organization.slug}`); redirect("/agenda?status=config-salva");
}

export async function createAppointmentAction(formData:FormData){
  await requireFeature("appointments"); const organization=await requireCurrentOrganization(); const start=field(formData,"start",40); const serviceId=field(formData,"service_id",80)||null; const professionalId=field(formData,"professional_user_id",80)||null; const leadId=field(formData,"lead_id",80)||null; const customerId=field(formData,"customer_id",80)||null; const durationRaw=field(formData,"duration_minutes",4); const duration=durationRaw?Number(durationRaw):0; const notes=field(formData,"notes",2000);
  if(!start||(!leadId&&!customerId)) redirect("/agenda?erro=campos"); if(durationRaw&&(!Number.isInteger(duration)||duration<15||duration>480)) redirect("/agenda?erro=duracao");
  const supabase=await createClient(); const {error}=await supabase.rpc("create_appointment",{p_organization_id:organization.id,p_lead_id:leadId,p_customer_id:customerId,p_service_id:serviceId,p_professional_user_id:professionalId,p_local_start:start,p_duration_minutes:duration,p_notes:notes});
  if(error) redirect(`/agenda?erro=${error.message.toLowerCase().includes("conflict")?"conflito":"salvar"}`); revalidatePath("/agenda"); redirect("/agenda?status=criado");
}

export async function updateAppointmentStatusAction(formData:FormData){
  await requireFeature("appointments"); const organization=await requireCurrentOrganization(); const id=field(formData,"appointment_id",80); const status=field(formData,"status",20); if(!id||!["scheduled","confirmed","completed","canceled","no_show"].includes(status)) redirect("/agenda?erro=campos");
  const supabase=await createClient(); const {error}=await supabase.rpc("update_appointment_status",{p_organization_id:organization.id,p_appointment_id:id,p_status:status}); if(error) redirect("/agenda?erro=salvar"); revalidatePath("/agenda");
}

export async function publicAppointmentAction(slug:string,formData:FormData){
  const name=field(formData,"name",160); const phone=field(formData,"phone",40); const serviceId=field(formData,"service_id",80); const start=field(formData,"start",40); const honeypot=field(formData,"website",120); if(honeypot) redirect(`/agendar/${slug}?status=recebido`); if(name.length<2||phone.length<8||!serviceId||!start) redirect(`/agendar/${slug}?erro=campos`);
  let allowed=false;
  try{const hash=await requestFingerprint(`${slug}:${phone}`); const rate=await consumeRateLimit({scope:"public_booking",identifierHash:hash,limit:8,windowSeconds:3600}); allowed=rate.allowed;}catch{redirect(`/agendar/${slug}?erro=seguranca`);}
  if(!allowed) redirect(`/agendar/${slug}?erro=limite`);
  const supabase=await createClient(); const {error}=await supabase.rpc("public_create_appointment",{p_slug:slug,p_service_id:serviceId,p_local_start:start,p_name:name,p_phone:phone}); if(error) redirect(`/agendar/${slug}?erro=${error.message.toLowerCase().includes("conflict")?"ocupado":"indisponivel"}`); revalidatePath(`/agendar/${slug}`); redirect(`/agendar/${slug}?status=confirmado`);
}
