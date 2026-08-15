import "server-only";
import { lookup } from "node:dns/promises";
import { isIP } from "node:net";

function privateV4(ip:string){
  const p=ip.split(".").map(Number);if(p.length!==4||p.some(n=>!Number.isInteger(n)||n<0||n>255))return true;
  const [a,b,c]=p;
  return a===0||a===10||a===127||a>=224
    ||(a===100&&b>=64&&b<=127)||(a===169&&b===254)||(a===172&&b>=16&&b<=31)||(a===192&&b===168)
    ||(a===192&&b===0&&c===0)||(a===192&&b===0&&c===2)||(a===198&&b>=18&&b<=19)
    ||(a===198&&b===51&&c===100)||(a===203&&b===0&&c===113);
}
function privateV6(ip:string){
  const v=ip.toLowerCase();
  if(v.startsWith("::ffff:")){const mapped=v.slice(7);if(isIP(mapped)===4)return privateV4(mapped);}
  return v==="::"||v==="::1"||v.startsWith("fc")||v.startsWith("fd")||v.startsWith("fe8")||v.startsWith("fe9")||v.startsWith("fea")||v.startsWith("feb")||v.startsWith("2001:db8:");
}
export function isPrivateOrReservedAddress(ip:string){return isIP(ip)===4?privateV4(ip):isIP(ip)===6?privateV6(ip):true;}

export async function validateWebhookUrl(raw:string){
  let url:URL;try{url=new URL(raw.trim());}catch{throw new Error("WEBHOOK_URL_INVALID");}
  if(url.protocol!=="https:"||url.username||url.password||url.hash)throw new Error("WEBHOOK_URL_HTTPS_REQUIRED");
  if(url.port&&url.port!=="443")throw new Error("WEBHOOK_URL_PORT_NOT_ALLOWED");
  const host=url.hostname.toLowerCase();
  if(host==="localhost"||host.endsWith(".localhost")||host.endsWith(".local")||host.endsWith(".internal"))throw new Error("WEBHOOK_URL_PRIVATE_HOST");
  if(isIP(host)){if(isPrivateOrReservedAddress(host))throw new Error("WEBHOOK_URL_PRIVATE_HOST");}
  else{
    const addresses=await lookup(host,{all:true,verbatim:true});if(!addresses.length)throw new Error("WEBHOOK_URL_DNS_EMPTY");
    if(addresses.some(item=>isPrivateOrReservedAddress(item.address)))throw new Error("WEBHOOK_URL_PRIVATE_HOST");
  }
  url.pathname=url.pathname||"/";return url.toString();
}
