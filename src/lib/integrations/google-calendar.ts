import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";
import { decryptIntegrationSecret,encryptIntegrationSecret } from "@/lib/communications/secret-box";
import { getPublicAppUrl } from "@/lib/env";

type TokenBundle={access_token:string;refresh_token:string;expires_at:number;scope?:string};
type TokenResponse={access_token?:string;refresh_token?:string;expires_in?:number;scope?:string;error?:string};

function oauthEnv(){
  const clientId=process.env.GOOGLE_OAUTH_CLIENT_ID;const clientSecret=process.env.GOOGLE_OAUTH_CLIENT_SECRET;
  if(!clientId||!clientSecret)throw new Error("GOOGLE_CALENDAR_NOT_CONFIGURED");return{clientId,clientSecret};
}
export function isGoogleCalendarConfigured(){return Boolean(process.env.GOOGLE_OAUTH_CLIENT_ID&&process.env.GOOGLE_OAUTH_CLIENT_SECRET&&process.env.INTEGRATION_ENCRYPTION_KEY);}
export function googleCalendarRedirectUri(){return process.env.GOOGLE_CALENDAR_REDIRECT_URI||`${getPublicAppUrl().replace(/\/$/,"")}/api/integrations/google-calendar/callback`;}
export function buildGoogleCalendarAuthorizationUrl(state:string){
  const {clientId}=oauthEnv();const url=new URL("https://accounts.google.com/o/oauth2/v2/auth");
  url.searchParams.set("client_id",clientId);url.searchParams.set("redirect_uri",googleCalendarRedirectUri());url.searchParams.set("response_type","code");
  url.searchParams.set("access_type","offline");url.searchParams.set("prompt","consent");url.searchParams.set("include_granted_scopes","true");url.searchParams.set("state",state);
  url.searchParams.set("scope","openid email https://www.googleapis.com/auth/calendar.events");return url.toString();
}
export async function exchangeGoogleCalendarCode(code:string){
  const {clientId,clientSecret}=oauthEnv();const response=await fetch("https://oauth2.googleapis.com/token",{method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded"},body:new URLSearchParams({code,client_id:clientId,client_secret:clientSecret,redirect_uri:googleCalendarRedirectUri(),grant_type:"authorization_code"}),cache:"no-store"});
  const json=await response.json() as TokenResponse;if(!response.ok||!json.access_token)throw new Error(`GOOGLE_OAUTH_EXCHANGE_${response.status}`);
  return{access_token:json.access_token,refresh_token:json.refresh_token||"",expires_at:Date.now()+Math.max(60,json.expires_in||3600)*1000,scope:json.scope};
}
export async function googleUserEmail(accessToken:string){
  const r=await fetch("https://openidconnect.googleapis.com/v1/userinfo",{headers:{Authorization:`Bearer ${accessToken}`},cache:"no-store"});if(!r.ok)return null;const j=await r.json() as {email?:unknown};return typeof j.email==="string"?j.email:null;
}
async function loadConnection(organizationId:string){
  const admin=createAdminClient();const {data:connection,error}=await admin.from("integration_connections").select("id,status,config").eq("organization_id",organizationId).eq("provider","google_calendar").eq("status","active").maybeSingle();
  if(error||!connection)throw new Error("GOOGLE_CALENDAR_CONNECTION_MISSING");const {data:secret}=await admin.from("integration_secrets").select("ciphertext,iv,auth_tag").eq("connection_id",connection.id).maybeSingle();if(!secret)throw new Error("GOOGLE_CALENDAR_SECRET_MISSING");
  const bundle=JSON.parse(decryptIntegrationSecret({ciphertext:secret.ciphertext,iv:secret.iv,authTag:secret.auth_tag})) as TokenBundle;return{admin,connection,bundle};
}
async function validAccessToken(organizationId:string){
  const loaded=await loadConnection(organizationId);if(loaded.bundle.access_token&&loaded.bundle.expires_at>Date.now()+60_000)return{...loaded,accessToken:loaded.bundle.access_token};
  if(!loaded.bundle.refresh_token)throw new Error("GOOGLE_CALENDAR_REFRESH_TOKEN_MISSING");const {clientId,clientSecret}=oauthEnv();const response=await fetch("https://oauth2.googleapis.com/token",{method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded"},body:new URLSearchParams({client_id:clientId,client_secret:clientSecret,refresh_token:loaded.bundle.refresh_token,grant_type:"refresh_token"}),cache:"no-store"});const json=await response.json() as TokenResponse;if(!response.ok||!json.access_token)throw new Error(`GOOGLE_OAUTH_REFRESH_${response.status}`);
  const bundle:TokenBundle={...loaded.bundle,access_token:json.access_token,expires_at:Date.now()+Math.max(60,json.expires_in||3600)*1000,scope:json.scope||loaded.bundle.scope};const encrypted=encryptIntegrationSecret(JSON.stringify(bundle));await loaded.admin.from("integration_secrets").update({ciphertext:encrypted.ciphertext,iv:encrypted.iv,auth_tag:encrypted.authTag,updated_at:new Date().toISOString()}).eq("connection_id",loaded.connection.id);return{...loaded,bundle,accessToken:bundle.access_token};
}
function eventId(appointmentId:string){return `saas${appointmentId.replace(/-/g,"").toLowerCase()}`;}
async function appointmentPayload(organizationId:string,appointmentId:string){
  const admin=createAdminClient();const {data:a,error}=await admin.from("appointments").select("id,organization_id,lead_id,customer_id,service_id,contact_name,starts_at,ends_at,status,notes").eq("organization_id",organizationId).eq("id",appointmentId).maybeSingle();if(error||!a)throw new Error("APPOINTMENT_NOT_FOUND");
  const [{data:org},{data:service},{data:lead},{data:customer}]=await Promise.all([
    admin.from("organizations").select("name,address,timezone").eq("id",organizationId).single(),
    a.service_id?admin.from("services").select("name").eq("id",a.service_id).maybeSingle():Promise.resolve({data:null}),
    a.lead_id?admin.from("leads").select("name").eq("id",a.lead_id).maybeSingle():Promise.resolve({data:null}),
    a.customer_id?admin.from("customers").select("name").eq("id",a.customer_id).maybeSingle():Promise.resolve({data:null})
  ]);
  const contact=a.contact_name||lead?.name||customer?.name||"Cliente";const summary=`${service?.name||"Atendimento"} — ${contact}`.slice(0,250);const appUrl=getPublicAppUrl().replace(/\/$/,"");
  return{admin,a,org,body:{id:eventId(a.id),summary,description:[a.notes?.trim(),`Gerenciado pela plataforma: ${appUrl}/agenda`].filter(Boolean).join("\n\n").slice(0,8000),location:org?.address||undefined,start:{dateTime:a.starts_at,timeZone:org?.timezone||"America/Sao_Paulo"},end:{dateTime:a.ends_at,timeZone:org?.timezone||"America/Sao_Paulo"}}};
}
export async function upsertGoogleCalendarAppointment(organizationId:string,appointmentId:string){
  const auth=await validAccessToken(organizationId);const payload=await appointmentPayload(organizationId,appointmentId);if(payload.a.status==="canceled")return deleteGoogleCalendarAppointment(organizationId,appointmentId);
  const calendarId=String(auth.connection.config?.calendar_id||"primary");const base=`https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(calendarId)}/events`;let response=await fetch(`${base}?sendUpdates=none`,{method:"POST",headers:{Authorization:`Bearer ${auth.accessToken}`,"Content-Type":"application/json"},body:JSON.stringify(payload.body)});
  if(response.status===409)response=await fetch(`${base}/${encodeURIComponent(payload.body.id)}?sendUpdates=none`,{method:"PATCH",headers:{Authorization:`Bearer ${auth.accessToken}`,"Content-Type":"application/json"},body:JSON.stringify(payload.body)});
  const json=await response.json().catch(()=>({})) as {id?:string;htmlLink?:string};if(!response.ok||!json.id)throw new Error(`GOOGLE_CALENDAR_EVENT_${response.status}`);
  await payload.admin.from("appointment_external_events").upsert({organization_id:organizationId,appointment_id:appointmentId,provider:"google_calendar",external_event_id:json.id,html_link:json.htmlLink||null,status:"active",last_synced_at:new Date().toISOString(),last_error:null},{onConflict:"appointment_id,provider"});return{id:json.id,htmlLink:json.htmlLink||null};
}
export async function deleteGoogleCalendarAppointment(organizationId:string,appointmentId:string){
  const auth=await validAccessToken(organizationId);const admin=auth.admin;const {data:mapping}=await admin.from("appointment_external_events").select("external_event_id").eq("organization_id",organizationId).eq("appointment_id",appointmentId).eq("provider","google_calendar").maybeSingle();const id=mapping?.external_event_id||eventId(appointmentId);const calendarId=String(auth.connection.config?.calendar_id||"primary");const response=await fetch(`https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(calendarId)}/events/${encodeURIComponent(id)}?sendUpdates=none`,{method:"DELETE",headers:{Authorization:`Bearer ${auth.accessToken}`}});if(!response.ok&&response.status!==404)throw new Error(`GOOGLE_CALENDAR_DELETE_${response.status}`);await admin.from("appointment_external_events").upsert({organization_id:organizationId,appointment_id:appointmentId,provider:"google_calendar",external_event_id:id,status:"canceled",last_synced_at:new Date().toISOString(),last_error:null},{onConflict:"appointment_id,provider"});return{id};
}
