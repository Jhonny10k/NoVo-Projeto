import "server-only";
import { createHmac,timingSafeEqual } from "node:crypto";

function webhookKey(secret:string){
  const encoded=secret.startsWith("whsec_")?secret.slice(6):secret;
  const key=Buffer.from(encoded,"base64");
  if(key.length<16)throw new Error("RESEND_WEBHOOK_SECRET_INVALID");
  return key;
}

export function isResendWebhookConfigured(){return Boolean(process.env.RESEND_WEBHOOK_SECRET);}

export function verifyResendWebhook(payload:string,headers:{id:string|null;timestamp:string|null;signature:string|null},nowSeconds=Math.floor(Date.now()/1000)){
  const secret=process.env.RESEND_WEBHOOK_SECRET;if(!secret)throw new Error("RESEND_WEBHOOK_NOT_CONFIGURED");
  const id=headers.id?.trim()||"";const timestamp=headers.timestamp?.trim()||"";const signatures=headers.signature?.trim()||"";
  if(!id||!/^\d{9,12}$/.test(timestamp)||!signatures)throw new Error("RESEND_WEBHOOK_HEADERS_INVALID");
  const ts=Number(timestamp);if(!Number.isFinite(ts)||Math.abs(nowSeconds-ts)>300)throw new Error("RESEND_WEBHOOK_TIMESTAMP_INVALID");
  const expected=createHmac("sha256",webhookKey(secret)).update(`${id}.${timestamp}.${payload}`,"utf8").digest();
  const valid=signatures.split(/\s+/).some(part=>{
    const [version,encoded]=part.split(",",2);if(version!=="v1"||!encoded)return false;
    try{const actual=Buffer.from(encoded,"base64");return actual.length===expected.length&&timingSafeEqual(actual,expected);}catch{return false;}
  });
  if(!valid)throw new Error("RESEND_WEBHOOK_SIGNATURE_INVALID");
  return{id,timestamp:ts};
}
