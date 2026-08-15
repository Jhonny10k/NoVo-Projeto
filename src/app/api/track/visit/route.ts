import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { consumeRateLimit, requestFingerprint } from "@/lib/security/rate-limit";

function text(value:unknown,max:number){return typeof value==="string"?value.trim().slice(0,max):"";}
export async function POST(request:Request){
  let body:Record<string,unknown>={};
  try{body=await request.json() as Record<string,unknown>;}catch{return NextResponse.json({ok:false},{status:400});}
  const slug=text(body.slug,120);const sessionId=text(body.session_id,100);if(!slug||sessionId.length<8)return NextResponse.json({ok:false},{status:400});
  try{
    const visitorHash=await requestFingerprint(`${slug}:${sessionId}`);
    const rate=await consumeRateLimit({scope:"site_visit",identifierHash:visitorHash,limit:80,windowSeconds:3600});
    if(!rate.allowed)return NextResponse.json({ok:true});
    const admin=createAdminClient();
    const {error}=await admin.rpc("record_site_visit",{
      p_slug:slug,p_visitor_hash:visitorHash,p_pathname:text(body.pathname,300)||"/",p_referrer_host:text(body.referrer,200)||null,
      p_utm_source:text(body.utm_source,120)||null,p_utm_medium:text(body.utm_medium,120)||null,p_utm_campaign:text(body.utm_campaign,160)||null,
      p_utm_content:text(body.utm_content,160)||null,p_utm_term:text(body.utm_term,160)||null
    });
    if(error)return NextResponse.json({ok:false},{status:500});
    return NextResponse.json({ok:true});
  }catch{return NextResponse.json({ok:false},{status:500});}
}
