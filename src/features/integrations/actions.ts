"use server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireUser } from "@/lib/auth/require-user";
import { encryptIntegrationSecret } from "@/lib/communications/secret-box";
import { verifyWhatsAppConnection } from "@/lib/communications/whatsapp";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { requireFeature } from "@/lib/plans/entitlements";
import { createAdminClient } from "@/lib/supabase/admin";

function field(fd:FormData,key:string,max=1000){const value=fd.get(key);return typeof value==="string"?value.trim().slice(0,max):"";}
async function context(){await requireFeature("whatsapp_official");const user=await requireUser();const organization=await requireCurrentOrganization();if(!["owner","admin"].includes(organization.role))redirect("/integracoes?erro=permissao");return{user,organization,admin:createAdminClient()};}

export async function saveWhatsAppConnectionAction(fd:FormData){
  const {user,organization,admin}=await context();const phoneNumberId=field(fd,"phone_number_id",40);const wabaId=field(fd,"waba_id",40);const token=field(fd,"access_token",5000);
  if(!/^[0-9]{5,40}$/.test(phoneNumberId)||!(/^[0-9]{5,40}$/.test(wabaId)))redirect("/integracoes?erro=campos");
  const {data:existing}=await admin.from("integration_connections").select("id").eq("organization_id",organization.id).eq("provider","whatsapp_cloud").maybeSingle();
  if(!existing&&!token)redirect("/integracoes?erro=token");
  const {data:connection,error}=await admin.from("integration_connections").upsert({organization_id:organization.id,provider:"whatsapp_cloud",status:"configured",config:{phone_number_id:phoneNumberId,waba_id:wabaId},last_error:null,created_by:user.id},{onConflict:"organization_id,provider"}).select("id").single();
  if(error||!connection)redirect("/integracoes?erro=salvar");
  if(token){const encrypted=encryptIntegrationSecret(token);const {error:secretError}=await admin.from("integration_secrets").upsert({connection_id:connection.id,ciphertext:encrypted.ciphertext,iv:encrypted.iv,auth_tag:encrypted.authTag,updated_at:new Date().toISOString()},{onConflict:"connection_id"});if(secretError)redirect("/integracoes?erro=salvar");}
  await admin.from("audit_logs").insert({organization_id:organization.id,actor_user_id:user.id,action:"integration.whatsapp_saved",entity_type:"integration",entity_id:connection.id});
  revalidatePath("/integracoes");redirect("/integracoes?status=salva");
}

export async function testWhatsAppConnectionAction(){
  const {user,organization,admin}=await context();let verified:{displayPhoneNumber:string|null;verifiedName:string|null;qualityRating:string|null};
  try{verified=await verifyWhatsAppConnection(organization.id);}catch(error){const message=error instanceof Error?error.message:"verification failed";await admin.from("integration_connections").update({status:"error",last_error:message.slice(0,500)}).eq("organization_id",organization.id).eq("provider","whatsapp_cloud");redirect("/integracoes?erro=verificacao");throw error;}
  const {data:connection}=await admin.from("integration_connections").select("id,config").eq("organization_id",organization.id).eq("provider","whatsapp_cloud").single();await admin.from("integration_connections").update({status:"active",last_verified_at:new Date().toISOString(),last_error:null,config:{...(connection?.config||{}),display_phone_number:verified.displayPhoneNumber,verified_name:verified.verifiedName,quality_rating:verified.qualityRating}}).eq("id",connection?.id);await admin.from("audit_logs").insert({organization_id:organization.id,actor_user_id:user.id,action:"integration.whatsapp_verified",entity_type:"integration",entity_id:connection?.id});revalidatePath("/integracoes");redirect("/integracoes?status=verificada");
}

export async function disconnectWhatsAppAction(){const {user,organization,admin}=await context();const {data:connection}=await admin.from("integration_connections").select("id").eq("organization_id",organization.id).eq("provider","whatsapp_cloud").maybeSingle();if(connection){await admin.from("integration_secrets").delete().eq("connection_id",connection.id);await admin.from("integration_connections").update({status:"disconnected",last_error:null}).eq("id",connection.id);await admin.from("audit_logs").insert({organization_id:organization.id,actor_user_id:user.id,action:"integration.whatsapp_disconnected",entity_type:"integration",entity_id:connection.id});}revalidatePath("/integracoes");redirect("/integracoes?status=desconectada");}


export async function disconnectGoogleCalendarAction(){
  await requireFeature("google_calendar");const user=await requireUser();const organization=await requireCurrentOrganization();if(!["owner","admin"].includes(organization.role))redirect("/integracoes?erro=permissao");const admin=createAdminClient();const {data:connection}=await admin.from("integration_connections").select("id").eq("organization_id",organization.id).eq("provider","google_calendar").maybeSingle();if(connection){await admin.from("integration_secrets").delete().eq("connection_id",connection.id);await admin.from("integration_connections").update({status:"disconnected",last_error:null}).eq("id",connection.id);await admin.from("audit_logs").insert({organization_id:organization.id,actor_user_id:user.id,action:"integration.google_calendar_disconnected",entity_type:"integration",entity_id:connection.id});}revalidatePath("/integracoes");redirect("/integracoes?status=google-calendar-desconectado");
}

export async function geocodeOrganizationAddressAction(){
  await requireFeature("google_maps");const user=await requireUser();const organization=await requireCurrentOrganization();if(!["owner","admin"].includes(organization.role))redirect("/integracoes?erro=permissao");const admin=createAdminClient();const {data:org}=await admin.from("organizations").select("address,city,state").eq("id",organization.id).maybeSingle();const address=[org?.address,org?.city,org?.state,"Brasil"].filter(Boolean).join(", ");if(address.length<5)redirect("/integracoes?erro=endereco");try{const {geocodeBrazilianAddress}=await import("@/lib/integrations/google-maps");const result=await geocodeBrazilianAddress(address);await admin.from("organizations").update({latitude:result.latitude,longitude:result.longitude,google_place_id:result.placeId,geocoded_address:result.formattedAddress,geocoded_at:new Date().toISOString()}).eq("id",organization.id);await admin.from("audit_logs").insert({organization_id:organization.id,actor_user_id:user.id,action:"integration.google_maps_geocoded",entity_type:"organization",entity_id:organization.id,metadata:{place_id:result.placeId}});}catch{redirect("/integracoes?erro=google_maps");}revalidatePath("/integracoes");revalidatePath(`/empresa/${organization.slug}`);redirect("/integracoes?status=endereco-validado");
}
