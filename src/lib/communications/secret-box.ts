import "server-only";
import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";

export type EncryptedSecret={ciphertext:string;iv:string;authTag:string};

function encryptionKey(){
  const raw=process.env.INTEGRATION_ENCRYPTION_KEY;
  if(!raw)throw new Error("INTEGRATION_ENCRYPTION_KEY_NOT_CONFIGURED");
  const key=Buffer.from(raw,"base64");
  if(key.length!==32)throw new Error("INTEGRATION_ENCRYPTION_KEY_INVALID");
  return key;
}

export function encryptIntegrationSecret(value:string):EncryptedSecret{
  const iv=randomBytes(12);const cipher=createCipheriv("aes-256-gcm",encryptionKey(),iv);
  const encrypted=Buffer.concat([cipher.update(value,"utf8"),cipher.final()]);
  return{ciphertext:encrypted.toString("base64"),iv:iv.toString("base64"),authTag:cipher.getAuthTag().toString("base64")};
}

export function decryptIntegrationSecret(secret:EncryptedSecret){
  const decipher=createDecipheriv("aes-256-gcm",encryptionKey(),Buffer.from(secret.iv,"base64"));
  decipher.setAuthTag(Buffer.from(secret.authTag,"base64"));
  return Buffer.concat([decipher.update(Buffer.from(secret.ciphertext,"base64")),decipher.final()]).toString("utf8");
}
