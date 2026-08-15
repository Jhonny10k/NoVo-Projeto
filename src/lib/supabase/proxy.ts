import { createServerClient, type CookieMethodsServer } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { isSupabaseConfigured, requireSupabaseEnv } from "@/lib/env";

const protectedPrefixes = ["/dashboard", "/onboarding", "/crm", "/clientes", "/orcamentos", "/tarefas", "/catalogo", "/assinatura", "/admin", "/site", "/integracoes", "/atendimento", "/desenvolvedores", "/white-label", "/unidades"];

export async function updateSession(request: NextRequest) {
  if (!isSupabaseConfigured()) return NextResponse.next({ request });

  const { url, key } = requireSupabaseEnv();
  let response = NextResponse.next({ request });

  const cookieMethods: CookieMethodsServer = {
    getAll() {
      return request.cookies.getAll();
    },
    setAll(cookiesToSet) {
      cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
      response = NextResponse.next({ request });
      cookiesToSet.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
    },
  };

  const supabase = createServerClient(url, key, { cookies: cookieMethods });

  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;
  const isProtected = protectedPrefixes.some((prefix) => request.nextUrl.pathname.startsWith(prefix));

  if (!claims && isProtected) {
    const urlToLogin = request.nextUrl.clone();
    urlToLogin.pathname = "/login";
    urlToLogin.searchParams.set("redirectTo", request.nextUrl.pathname);
    return NextResponse.redirect(urlToLogin);
  }

  if (claims && ["/login", "/cadastro"].includes(request.nextUrl.pathname)) {
    const urlToDashboard = request.nextUrl.clone();
    urlToDashboard.pathname = "/dashboard";
    urlToDashboard.search = "";
    return NextResponse.redirect(urlToDashboard);
  }

  return response;
}
