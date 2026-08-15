"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { getPublicAppUrl, isSupabaseConfigured } from "@/lib/env";
import { consumeRateLimit, requestFingerprint } from "@/lib/security/rate-limit";

function text(formData: FormData, key: string) {
  const value = formData.get(key);
  return typeof value === "string" ? value.trim() : "";
}

async function authRateAllowed(scope: string, identity: string, limit: number, windowSeconds: number) {
  try {
    const identifierHash = await requestFingerprint(identity);
    const result = await consumeRateLimit({ scope, identifierHash, limit, windowSeconds });
    return result.allowed;
  } catch {
    return false;
  }
}

export async function signInAction(formData: FormData) {
  if (!isSupabaseConfigured()) redirect("/login?erro=config");

  const email = text(formData, "email").toLowerCase();
  const password = text(formData, "password");

  if (!email || !password) redirect("/login?erro=campos");
  if (!(await authRateAllowed("auth_signin", email, 10, 900))) redirect("/login?erro=limite");

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });

  if (error) redirect("/login?erro=credenciais");
  redirect("/dashboard");
}

export async function signUpAction(formData: FormData) {
  if (!isSupabaseConfigured()) redirect("/cadastro?erro=config");

  const name = text(formData, "name");
  const email = text(formData, "email").toLowerCase();
  const password = text(formData, "password");

  if (name.length < 2 || !email || password.length < 8) redirect("/cadastro?erro=campos");
  if (!(await authRateAllowed("auth_signup", email, 5, 3600))) redirect("/cadastro?erro=limite");

  const supabase = await createClient();
  const { error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      emailRedirectTo: `${getPublicAppUrl()}/auth/callback`,
      data: { name }
    }
  });

  if (error) redirect("/cadastro?erro=cadastro");
  redirect("/cadastro?sucesso=verifique-email");
}

export async function requestPasswordResetAction(formData: FormData) {
  if (!isSupabaseConfigured()) redirect("/esqueci-senha?erro=config");

  const email = text(formData, "email").toLowerCase();
  if (!email) redirect("/esqueci-senha?erro=campos");
  if (!(await authRateAllowed("auth_password_reset", email, 5, 3600))) redirect("/esqueci-senha?erro=limite");

  const supabase = await createClient();
  // Resposta genérica evita enumeração de contas.
  await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${getPublicAppUrl()}/auth/callback?next=${encodeURIComponent("/redefinir-senha")}`
  });
  redirect("/esqueci-senha?status=enviado");
}

export async function updateRecoveredPasswordAction(formData: FormData) {
  const password = text(formData, "password");
  const confirmation = text(formData, "confirm_password");
  if (password.length < 8 || password !== confirmation) redirect("/redefinir-senha?erro=senha");

  const supabase = await createClient();
  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) redirect("/esqueci-senha?erro=sessao");

  const { error } = await supabase.auth.updateUser({ password });
  if (error) redirect("/redefinir-senha?erro=salvar");
  await supabase.auth.signOut();
  redirect("/login?status=senha-alterada");
}

export async function setPasswordAction(formData: FormData) {
  const password = text(formData, "password");
  const confirmation = text(formData, "confirm_password");
  if (password.length < 8 || password !== confirmation) redirect("/definir-senha?erro=senha");

  const supabase = await createClient();
  const { error } = await supabase.auth.updateUser({ password });
  if (error) redirect("/definir-senha?erro=salvar");
  redirect("/dashboard");
}

export async function signOutAction() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/");
}
