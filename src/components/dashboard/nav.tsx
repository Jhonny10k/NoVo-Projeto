import Link from "next/link";
import { signOutAction } from "@/features/auth/actions";
import { getCurrentOrganization } from "@/lib/organizations/current";
import { createClient } from "@/lib/supabase/server";

type NavItem = { label: string; href: string };
type NavGroup = { label: string; items: NavItem[] };

const menuGroups: NavGroup[] = [
  {
    label: "Vendas",
    items: [
      { label: "CRM", href: "/crm" },
      { label: "Atendimento", href: "/atendimento" },
      { label: "Clientes", href: "/clientes" },
      { label: "Orçamentos", href: "/orcamentos" },
      { label: "Catálogo", href: "/catalogo" }
    ]
  },
  {
    label: "Operação",
    items: [
      { label: "Agenda", href: "/agenda" },
      { label: "Tarefas", href: "/tarefas" },
      { label: "Automações", href: "/automacoes" }
    ]
  },
  {
    label: "Crescimento",
    items: [
      { label: "Analytics", href: "/analytics" },
      { label: "Assistente IA", href: "/assistente-ia" },
      { label: "Site", href: "/site" },
      { label: "Marca", href: "/white-label" }
    ]
  },
  {
    label: "Gestão",
    items: [
      { label: "Integrações", href: "/integracoes" },
      { label: "Desenvolvedores", href: "/desenvolvedores" },
      { label: "Equipe", href: "/equipe" },
      { label: "Unidades", href: "/unidades" },
      { label: "Plano", href: "/assinatura" },
      { label: "Empresa", href: "/configuracoes" }
    ]
  }
];

function initials(value: string) {
  return value
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() ?? "")
    .join("") || "ND";
}

function DesktopGroup({ group }: { group: NavGroup }) {
  return (
    <details className="nav-menu">
      <summary>
        {group.label}
        <span className="nav-chevron" aria-hidden="true">⌄</span>
      </summary>
      <div className="nav-dropdown">
        {group.items.map((item) => (
          <Link key={item.href} href={item.href}>
            <span className="nav-item-dot" aria-hidden="true" />
            {item.label}
          </Link>
        ))}
      </div>
    </details>
  );
}

export async function DashboardNav({ organizationName }: { organizationName: string }) {
  const organization = await getCurrentOrganization();
  let branding: { brand_name: string | null; logo_url: string | null; primary_color: string | null } | null = null;

  if (organization) {
    try {
      const supabase = await createClient();
      const { data } = await supabase
        .from("organization_branding")
        .select("brand_name,logo_url,primary_color")
        .eq("organization_id", organization.id)
        .maybeSingle();
      branding = data;
    } catch {
      branding = null;
    }
  }

  const displayName = branding?.brand_name || organizationName;
  const brandInitials = initials(displayName);

  return (
    <header
      className="app-topbar"
      style={branding?.primary_color ? { borderTop: `3px solid ${branding.primary_color}` } : undefined}
    >
      <div className="container-shell flex min-h-[68px] items-center justify-between gap-3">
        <div className="brand-lockup flex min-w-0 items-center gap-3">
          {branding?.logo_url ? (
            <img src={branding.logo_url} alt="" className="brand-logo" />
          ) : (
            <span className="brand-mark" aria-hidden="true">{brandInitials}</span>
          )}
          <div className="min-w-0">
            <Link href="/dashboard" className="block truncate text-[.93rem] font-extrabold tracking-tight text-slate-900">
              {displayName}
            </Link>
            <p className="mt-0.5 truncate text-[.7rem] font-medium text-slate-500">Central da operação</p>
          </div>
        </div>

        <nav className="hidden items-center gap-1 lg:flex" aria-label="Navegação do painel">
          <Link href="/dashboard" className="nav-direct">Visão geral</Link>
          {menuGroups.map((group) => <DesktopGroup key={group.label} group={group} />)}
        </nav>

        <div className="hidden items-center gap-2 lg:flex">
          <Link href="/notificacoes" className="btn-ghost min-h-[38px] px-3" aria-label="Abrir notificações">Notificações</Link>
          <details className="nav-menu account-menu">
            <summary className="account-summary" aria-label="Abrir menu da conta">{brandInitials}</summary>
            <div className="nav-dropdown">
              <Link href="/perfil"><span className="nav-item-dot" aria-hidden="true" />Meu perfil</Link>
              <Link href="/assinatura"><span className="nav-item-dot" aria-hidden="true" />Plano e cobrança</Link>
              <div className="mobile-nav-divider" />
              <form action={signOutAction}>
                <button type="submit" className="nav-form-button mobile-nav-link">Sair da conta</button>
              </form>
            </div>
          </details>
        </div>

        <details className="mobile-nav lg:hidden">
          <summary className="mobile-menu-summary" aria-label="Abrir menu de navegação">
            <span className="hamburger" aria-hidden="true"><i /><i /><i /></span>
          </summary>
          <nav className="mobile-nav-panel" aria-label="Navegação mobile">
            <Link href="/dashboard" className="mobile-nav-home">Visão geral</Link>
            {menuGroups.map((group) => (
              <div key={group.label}>
                <p className="mobile-nav-section">{group.label}</p>
                {group.items.map((item) => (
                  <Link key={item.href} href={item.href} className="mobile-nav-link">
                    <span className="nav-item-dot" aria-hidden="true" />
                    {item.label}
                  </Link>
                ))}
              </div>
            ))}
            <div className="mobile-nav-divider" />
            <p className="mobile-nav-section">Conta</p>
            <Link href="/notificacoes" className="mobile-nav-link">Notificações</Link>
            <Link href="/perfil" className="mobile-nav-link">Meu perfil</Link>
            <form action={signOutAction}>
              <button type="submit" className="nav-form-button mobile-nav-link">Sair da conta</button>
            </form>
          </nav>
        </details>
      </div>
    </header>
  );
}
