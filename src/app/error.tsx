"use client";

export default function GlobalError({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <html lang="pt-BR">
      <body>
        <main className="container-shell grid min-h-screen place-items-center py-10">
          <section className="card max-w-xl p-8 text-center">
            <h1 className="text-3xl font-black">Algo não saiu como esperado</h1>
            <p className="muted mt-3">Tente novamente. Se o problema continuar, registre o erro nos logs do ambiente.</p>
            <button className="btn-primary mt-6" onClick={() => reset()}>Tentar novamente</button>
          </section>
        </main>
      </body>
    </html>
  );
}
