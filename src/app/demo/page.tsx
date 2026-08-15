import Link from "next/link";
import { MarketingHeader } from "@/components/marketing/header";

export default function DemoPage() {
  const demoEnabled = process.env.DEMO_MODE === "true";

  return (
    <>
      <MarketingHeader />
      <main className="container-shell py-14">
        <h1 className="text-4xl font-black">Demonstração</h1>
        {demoEnabled ? (
          <div className="card mt-7 p-6">
            <p className="text-sm font-bold uppercase tracking-widest text-blue-700">DEMO MODE</p>
            <h2 className="mt-2 text-2xl font-black">Ambiente demonstrativo isolado</h2>
            <p className="muted mt-3">Esta área está explicitamente marcada como demonstração e não utiliza dados de clientes reais.</p>
          </div>
        ) : (
          <div className="card mt-7 p-6">
            <h2 className="font-bold">Demonstração desativada</h2>
            <p className="muted mt-2">O modo de demonstração só é exibido quando <code>DEMO_MODE=true</code>.</p>
            <Link href="/cadastro" className="btn-primary mt-5">Criar conta</Link>
          </div>
        )}
      </main>
    </>
  );
}
