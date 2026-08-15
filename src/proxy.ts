import type { NextRequest } from "next/server";
import { updateSession } from "@/lib/supabase/proxy";
import { customDomainRewrite } from "@/lib/white-label/domain-rewrite";

export async function proxy(request: NextRequest) {
  const rewritten=await customDomainRewrite(request);
  if(rewritten)return rewritten;
  return updateSession(request);
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)"]
};
