import "server-only";
import { createHash } from "node:crypto";
import { headers } from "next/headers";
import { createAdminClient } from "@/lib/supabase/admin";

export type RateLimitResult = {
  allowed: boolean;
  count: number;
  limit: number;
  reset_at: string;
};

function hashIdentifier(value: string) {
  const salt = process.env.RATE_LIMIT_SALT;
  if (!salt) throw new Error("RATE_LIMIT_SALT não configurado.");
  return createHash("sha256").update(`${salt}:${value}`).digest("hex");
}

export async function requestFingerprint(extra = "") {
  const requestHeaders = await headers();
  const forwarded = requestHeaders.get("x-forwarded-for")?.split(",")[0]?.trim();
  const realIp = requestHeaders.get("x-real-ip")?.trim();
  const ip = forwarded || realIp || "unknown";
  const userAgent = requestHeaders.get("user-agent")?.slice(0, 180) ?? "unknown";
  return hashIdentifier(`${ip}:${userAgent}:${extra}`);
}

export async function consumeRateLimit(input: {
  scope: string;
  identifierHash: string;
  limit: number;
  windowSeconds: number;
}): Promise<RateLimitResult> {
  const admin = createAdminClient();
  const { data, error } = await admin.rpc("consume_rate_limit", {
    p_scope: input.scope,
    p_identifier_hash: input.identifierHash,
    p_limit: input.limit,
    p_window_seconds: input.windowSeconds
  });
  if (error) throw new Error(`Falha no rate limit: ${error.message}`);
  return data as RateLimitResult;
}
