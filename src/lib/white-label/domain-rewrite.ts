import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";
import { requireSupabaseEnv } from "@/lib/env";

export async function customDomainRewrite(request:NextRequest){
  if(request.nextUrl.pathname!=="/")return null;
  const host=(request.headers.get("x-forwarded-host")||request.headers.get("host")||"").split(":")[0].toLowerCase();if(!host||host==="localhost")return null;
  let appHost="";try{appHost=new URL(process.env.NEXT_PUBLIC_APP_URL||"http://localhost").hostname.toLowerCase();}catch{}
  if(host===appHost||host.endsWith(".vercel.app"))return null;
  try{
    const {url,key}=requireSupabaseEnv();const response=await fetch(`${url}/rest/v1/rpc/resolve_public_custom_domain`,{method:"POST",headers:{apikey:key,authorization:`Bearer ${key}`,"content-type":"application/json"},body:JSON.stringify({p_hostname:host}),cache:"no-store"});if(!response.ok)return null;const slug=await response.json();if(typeof slug!=="string"||!slug)return null;
    const target=request.nextUrl.clone();target.pathname=`/empresa/${encodeURIComponent(slug)}`;return NextResponse.rewrite(target);
  }catch{return null;}
}
