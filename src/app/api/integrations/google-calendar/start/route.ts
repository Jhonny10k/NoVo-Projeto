import { randomUUID } from "node:crypto";
import { NextResponse } from "next/server";
import { requireUser } from "@/lib/auth/require-user";
import { buildGoogleCalendarAuthorizationUrl,isGoogleCalendarConfigured } from "@/lib/integrations/google-calendar";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { hasFeature } from "@/lib/plans/entitlements";
import { createAdminClient } from "@/lib/supabase/admin";

export const runtime="nodejs";
export async function GET(){const user=await requireUser();const organization=await requireCurrentOrganization();if(!["owner","admin"].includes(organization.role))return NextResponse.redirect(new URL("/integracoes?erro=permissao",process.env.NEXT_PUBLIC_APP_URL||"http://localhost:3000"));if(!(await hasFeature("google_calendar"))||!isGoogleCalendarConfigured())return NextResponse.redirect(new URL("/integracoes?erro=google_calendar_config",process.env.NEXT_PUBLIC_APP_URL||"http://localhost:3000"));const state=randomUUID();const admin=createAdminClient();await admin.from("oauth_states").delete().lt("expires_at",new Date().toISOString());const {error}=await admin.from("oauth_states").insert({id:state,provider:"google_calendar",organization_id:organization.id,user_id:user.id,expires_at:new Date(Date.now()+10*60*1000).toISOString()});if(error)return NextResponse.redirect(new URL("/integracoes?erro=oauth_state",process.env.NEXT_PUBLIC_APP_URL||"http://localhost:3000"));return NextResponse.redirect(buildGoogleCalendarAuthorizationUrl(state));}
