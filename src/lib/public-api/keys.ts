import "server-only";
import { createHmac, randomBytes } from "node:crypto";

export const publicApiScopes = ["leads:read","leads:write","customers:read","quotes:read"] as const;
export type PublicApiScope = (typeof publicApiScopes)[number];

function pepper(){
  const value=process.env.PUBLIC_API_KEY_PEPPER;
  if(!value || value.length<32) throw new Error("PUBLIC_API_KEY_PEPPER_NOT_CONFIGURED");
  return value;
}

export function generatePublicApiKey(){
  const secret=`nd_live_${randomBytes(32).toString("base64url")}`;
  return {secret,prefix:secret.slice(0,16),hash:hashPublicApiKey(secret)};
}

export function hashPublicApiKey(secret:string){
  return createHmac("sha256",pepper()).update(secret,"utf8").digest("hex");
}

export function parseScopes(value:FormDataEntryValue[]){
  const scopes=value.filter((item):item is string=>typeof item==="string"&&publicApiScopes.includes(item as PublicApiScope));
  return [...new Set(scopes)] as PublicApiScope[];
}
