"use client";

import { useEffect } from "react";

type Tracking = { utm_source?:string; utm_medium?:string; utm_campaign?:string; utm_content?:string; utm_term?:string };

export function VisitTracker({slug,tracking={}}:{slug:string;tracking?:Tracking}) {
  const { utm_source, utm_medium, utm_campaign, utm_content, utm_term } = tracking;
  useEffect(()=>{
    try {
      const sessionKey="saas_visit_session";
      let sessionId=sessionStorage.getItem(sessionKey);
      if(!sessionId){sessionId=crypto.randomUUID();sessionStorage.setItem(sessionKey,sessionId);}
      const pageKey=`saas_visit:${slug}:${location.pathname}`;
      if(sessionStorage.getItem(pageKey))return;
      sessionStorage.setItem(pageKey,"1");
      const referrer=document.referrer ? (()=>{try{return new URL(document.referrer).hostname.slice(0,200);}catch{return "";}})() : "";
      void fetch("/api/track/visit",{method:"POST",headers:{"content-type":"application/json"},keepalive:true,body:JSON.stringify({slug,pathname:location.pathname,referrer,session_id:sessionId,utm_source,utm_medium,utm_campaign,utm_content,utm_term})});
    } catch { /* Analytics nunca deve bloquear a experiência pública. */ }
  },[slug,utm_source,utm_medium,utm_campaign,utm_content,utm_term]);
  return null;
}
