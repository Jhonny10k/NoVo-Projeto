import Link from "next/link";
import { MarketingHeader } from "@/components/marketing/header";
import { MarketingFooter } from "@/components/marketing/footer";
import { isSupabaseConfigured } from "@/lib/env";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Plan = {
  id: string;
  name: string;
  description: string | null;
  price_monthly_cents: number;
  features: string[];
};

function formatMoney(cents: number) {
  return new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(cents / 100);
}

export default async function PlansPage() {
  let plans: Plan[] = [];

  if (isSupabaseConfigured()) {
    const supabase = await createClient();
    const { data } = await supabase
      .from("plans")
      .select("id,name,description,price_monthly_cents,features")
      .eq("active", true)
      .order("sort_order");

    plans = (data ?? []) as Plan[];
  }

  return (
    <>
      <MarketingHeader />
      <main className="container-shell py-14">
        <h1 className="text-4xl font-black">Planos</h1>
        <p className="muted mt-3 max-w-2xl">Preços e recursos são carregados do banco; não ficam fixos na interface.</p>

        {plans.length > 0 ? (
          <section className="mt-8 grid gap-4 lg:grid-cols-3">
            {plans.map((plan) => (
              <article key={plan.id} className="card p-6">
                <h2 className="text-xl font-black">{plan.name}</h2>
                {plan.description ? <p className="muted mt-2">{plan.description}</p> : null}
                <p className="mt-5 text-3xl font-black">
                  {formatMoney(plan.price_monthly_cents)}
                  <span className="muted text-sm font-normal">/mês</span>
                </p>
                <ul className="mt-5 grid gap-2 text-sm">
                  {plan.features.map((feature) => <li key={feature}>• {feature}</li>)}
                </ul>
                <Link href="/cadastro" className="btn-primary mt-6">Começar</Link>
              </article>
            ))}
          </section>
        ) : (
          <div className="card mt-8 p-6">
            <h2 className="font-bold">Planos ainda não carregados</h2>
            <p className="muted mt-2">Configure o Supabase e execute as migrations para carregar os planos administráveis.</p>
          </div>
        )}
      </main>
      <MarketingFooter />
    </>
  );
}
