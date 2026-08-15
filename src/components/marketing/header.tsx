import Link from "next/link";
import { APP_NAME } from "@/lib/brand";

export function MarketingHeader() {
  return (
    <header className="border-b border-black/5 bg-white">
      <div className="container-shell flex min-h-16 items-center justify-between gap-4">
        <Link href="/" className="font-extrabold tracking-tight">{APP_NAME}</Link>
        <nav aria-label="Navegação principal" className="flex items-center gap-3">
          <Link href="/planos" className="text-sm font-semibold">Planos</Link>
          <Link href="/contato" className="text-sm font-semibold">Contato</Link>
          <Link href="/login" className="btn-secondary">Entrar</Link>
          <Link href="/cadastro" className="btn-primary">Começar agora</Link>
        </nav>
      </div>
    </header>
  );
}
