import { redirect } from "next/navigation";
import { requireUser } from "@/lib/auth/require-user";
import { getCurrentOrganization } from "@/lib/organizations/current";
import { createOrganizationAction } from "@/features/organizations/actions";

type OnboardingProps = {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export const dynamic = "force-dynamic";

export default async function OnboardingPage({ searchParams }: OnboardingProps) {
  await requireUser();
  const existing = await getCurrentOrganization();
  if (existing) redirect("/dashboard");

  const params = await searchParams;
  const hasError = typeof params.erro === "string";

  return (
    <main className="container-shell py-10">
      <section className="card mx-auto max-w-2xl p-7 sm:p-9">
        <p className="text-sm font-bold uppercase tracking-widest text-blue-700">Onboarding</p>
        <h1 className="mt-2 text-3xl font-black">Sobre sua empresa</h1>
        <p className="muted mt-2">Esta etapa cria a organização e o isolamento dos dados.</p>
        {hasError ? <p role="alert" className="mt-5 rounded-lg bg-amber-50 p-3 text-sm">Não foi possível salvar. Revise os campos.</p> : null}

        <form action={createOrganizationAction} className="mt-7 grid gap-4 sm:grid-cols-2">
          <label className="field sm:col-span-2"><span>Nome da empresa</span><input name="name" required minLength={2} /></label>
          <label className="field"><span>Segmento</span><input name="segment" placeholder="Ex.: Oficina" required /></label>
          <label className="field"><span>WhatsApp</span><input name="whatsapp" inputMode="tel" /></label>
          <label className="field"><span>Telefone</span><input name="phone" inputMode="tel" /></label>
          <label className="field"><span>Cidade</span><input name="city" required /></label>
          <label className="field"><span>Estado (UF)</span><input name="state" required minLength={2} maxLength={2} /></label>
          <div className="sm:col-span-2"><button className="btn-primary" type="submit">Criar meu espaço</button></div>
        </form>
      </section>
    </main>
  );
}
