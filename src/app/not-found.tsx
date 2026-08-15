import Link from "next/link";

export default function NotFoundPage() {
  return (
    <main className="container-shell grid min-h-screen place-items-center py-10">
      <section className="card max-w-xl p-8 text-center">
        <p className="text-sm font-bold text-blue-700">404</p>
        <h1 className="mt-2 text-3xl font-black">Página não encontrada</h1>
        <p className="muted mt-3">O endereço informado não existe ou não está disponível.</p>
        <Link href="/" className="btn-primary mt-6">Voltar ao início</Link>
      </section>
    </main>
  );
}
