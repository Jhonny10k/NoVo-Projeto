"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { parseMoneyToCents } from "@/lib/format";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { requireFeature } from "@/lib/plans/entitlements";
import { createClient } from "@/lib/supabase/server";

function field(formData:FormData,key:string,max=1000){const v=formData.get(key);return typeof v==="string"?v.trim().slice(0,max):"";}
async function context(){await requireFeature("automations");const organization=await requireCurrentOrganization();if(!["owner","admin"].includes(organization.role))redirect("/automacoes?erro=permissao");return {organization,supabase:await createClient()};}

export async function createAutomationAction(formData:FormData){
  const {organization,supabase}=await context(); const name=field(formData,"name",160); const trigger=field(formData,"trigger_event",50); const actionType=field(formData,"action_type",30);
  const conditions:Record<string,unknown>={}; const source=field(formData,"condition_source",80); const status=field(formData,"condition_status",80); const tag=field(formData,"condition_tag",50); const minValue=field(formData,"condition_min_value",40);
  const afterMinutes=field(formData,"condition_after_minutes",10); const inactiveDays=field(formData,"condition_inactive_days",10); const runAtLocal=field(formData,"condition_run_at_local",40);
  if(source)conditions.source=source;if(status)conditions.status=status;if(tag)conditions.tag=tag;if(minValue){const cents=parseMoneyToCents(minValue);if(cents==null||cents<0)redirect("/automacoes?erro=condicao");conditions.min_value_cents=cents;}
  if(trigger==="lead_no_response"){const value=Number(afterMinutes);if(!Number.isInteger(value)||value<15||value>525600)redirect("/automacoes?erro=condicao");conditions.after_minutes=value;}
  else if(trigger==="customer_inactive"){const value=Number(inactiveDays);if(!Number.isInteger(value)||value<1||value>3650)redirect("/automacoes?erro=condicao");conditions.inactive_days=value;}
  else if(trigger==="date_specific"){if(!runAtLocal)redirect("/automacoes?erro=condicao");conditions.run_at_local=runAtLocal;}
  let action:Record<string,unknown>;
  if(actionType==="create_task"){const title=field(formData,"action_title",200);const priority=field(formData,"action_priority",20)||"medium";const due=Number(field(formData,"action_due_minutes",10)||"0");if(title.length<2||!["low","medium","high","urgent"].includes(priority)||!Number.isInteger(due)||due<0||due>43200)redirect("/automacoes?erro=acao");action={type:"create_task",title,description:field(formData,"action_body",2000),priority,due_minutes:due};}
  else if(actionType==="add_tag"){const value=field(formData,"action_value",50);if(!value)redirect("/automacoes?erro=acao");action={type:"add_tag",tag:value};}
  else if(actionType==="move_stage"){const value=field(formData,"action_value",80);if(!value)redirect("/automacoes?erro=acao");action={type:"move_stage",stage_key:value};}
  else if(actionType==="notify_team"){const title=field(formData,"action_title",160);if(title.length<2)redirect("/automacoes?erro=acao");action={type:"notify_team",title,body:field(formData,"action_body",1000)};}
  else {redirect("/automacoes?erro=acao");throw new Error("redirect");}
  if(name.length<2)redirect("/automacoes?erro=campos");
  const {error}=await supabase.rpc("save_automation",{p_organization_id:organization.id,p_automation_id:null,p_name:name,p_trigger_event:trigger,p_conditions:conditions,p_actions:[action],p_active:true});if(error)redirect("/automacoes?erro=salvar");revalidatePath("/automacoes");redirect("/automacoes?status=criada");
}

export async function setAutomationActiveAction(formData:FormData){const {organization,supabase}=await context();const id=field(formData,"automation_id",80);const active=field(formData,"active",10)==="true";if(!id)redirect("/automacoes?erro=campos");const {error}=await supabase.rpc("set_automation_active",{p_organization_id:organization.id,p_automation_id:id,p_active:active});if(error)redirect("/automacoes?erro=salvar");revalidatePath("/automacoes");}

export async function dryRunAutomationAction(formData:FormData){const {organization,supabase}=await context();const id=field(formData,"automation_id",80);if(!id)redirect("/automacoes?erro=campos");const {error}=await supabase.rpc("dry_run_automation",{p_organization_id:organization.id,p_automation_id:id});if(error)redirect("/automacoes?erro=teste");revalidatePath("/automacoes");redirect("/automacoes?status=teste");}
