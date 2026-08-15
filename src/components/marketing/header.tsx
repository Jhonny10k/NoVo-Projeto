import Link from "next/link";
import { APP_NAME } from "@/lib/brand";

export function MarketingHeader() {
  const brandInitial = APP_NAME.trim().charAt(0).toUpperCase() || "N";

  return (
    <header className="marketing-header">
      <div className="container-shell flex min-h-[68px] items-center justify-between gap-3">
        <Link href="/" className="marketing-brand" aria-label={`${APP_NAME} — início`}>
          <span className="marketing-brand-badge" aria-hidden="true">{brandInitial}</span>
          <span>{APP_NAME}</span>
        </Link>

        <nav aria-label="Navegação principal" className="hidden items-center gap-1 md:flex">
          <Link href="/planos" className="marketing-link">Planos</Link>
          <Link href="/contato" className="marketing-link">Contato</Link>
          <span className="mx-1 h-6 w-px bg-slate-200" aria-hidden="true" />
          <Link href="/login" className="btn-secondary min-h-10">Entrar</Link>
          <Link href="/cadastro" className="btn-primary min-h-10">Começar agora</Link>
        </nav>

        <details className="mobile-nav md:hidden">
          <summary className="mobile-menu-summary" aria-label="Abrir navegação principal">
            <span className="hamburger" aria-hidden="true"><i /><i /><i /></span>
          </summary>
          <nav className="mobile-nav-panel" aria-label="Navegação principal no celular">
            <p className="mobile-nav-section">Conheça</p>
            <Link href="/planos" className="mobile-nav-link">Planos</Link>
            <Link href="/contato" className="mobile-nav-link">Contato</Link>
            <div className="mobile-nav-divider" />
            <Link href="/login" className="mobile-nav-link">Entrar na conta</Link>
            <Link href="/cadastro" className="mobile-nav-home mt-1">Criar minha conta</Link>
          </nav>
        </details>
      </div>
    </header>
  );
}
