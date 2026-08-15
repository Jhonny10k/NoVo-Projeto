import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function requireUser() {
  const supabase = await createClient();
  const { data, error } = await supabase.auth.getClaims();

  if (error || !data?.claims?.sub) redirect("/login");

  return {
    id: data.claims.sub,
    email: typeof data.claims.email === "string" ? data.claims.email : null
  };
}
