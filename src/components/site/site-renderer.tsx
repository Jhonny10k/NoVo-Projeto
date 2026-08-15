import type { CSSProperties } from "react";

export type SiteSectionData = {
  id: string;
  type: string;
  enabled: boolean;
  sort_order: number;
  content: Record<string, unknown>;
};

export type SiteRenderData = {
  organization: { name: string; slug: string; segment: string | null; whatsapp: string | null; phone: string | null; city: string | null; state: string | null; address?: string | null; latitude?: number | null; longitude?: number | null; geocoded_address?: string | null };
  site: { headline: string | null; subheadline: string | null; about: string | null; primary_color?: string | null; cover_image_url?: string | null } | null;
  sections: SiteSectionData[];
  products: Array<{ id: string; name: string; description: string | null; price_cents: number | null; promotional_price_cents: number | null; image_url: string | null }>;
  services: Array<{ id: string; name: string; description: string | null; starting_price_cents: number | null; image_url: string | null }>;
  branding?: { brand_name?: string | null; logo_url?: string | null; favicon_url?: string | null; primary_color?: string | null; hide_platform_branding?: boolean; primary_domain?: string | null };
};

type Props = {
  content: SiteRenderData;
  quoteStatus?: string;
  quoteAction?: (formData: FormData) => void | Promise<void>;
  preview?: boolean;
  tracking?: { utm_source?:string; utm_medium?:string; utm_campaign?:string; utm_content?:string; utm_term?:string };
};

function text(value: unknown, fallback = "") { return typeof value === "string" && value.trim() ? value.trim() : fallback; }
function money(cents: number | null) { return cents == null ? null : new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(cents / 100); }
function targetHref(target: unknown, whatsapp: string | null, slug: string) {
  if (target === "whatsapp" && whatsapp) return `https://wa.me/${whatsapp.replace(/\D/g, "")}`;
  if (target === "contact") return "#contato";
  if (target === "booking") return `/agendar/${encodeURIComponent(slug)}`;
  return "#orcamento";
}

export function SiteRenderer({ content, quoteStatus = "", quoteAction, preview = false, tracking = {} }: Props) {
  const preferredColor=content.branding?.primary_color||content.site?.primary_color||"";
  const accent = /^#[0-9a-f]{6}$/i.test(preferredColor) ? preferredColor : "#2457d6";
  const sections = [...(content.sections ?? [])].filter((section) => section.enabled).sort((a,b) => a.sort_order - b.sort_order);
  const style = { "--site-accent": accent } as CSSProperties;

  return <main style={style} className={preview ? "bg-white" : ""}>
    {content.branding?.logo_url||content.branding?.brand_name?<header className="border-b border-black/5 bg-white"><div className="container-shell flex min-h-16 items-center gap-3 py-2">{content.branding?.logo_url?<img src={content.branding.logo_url} alt="" className="h-10 w-10 rounded-xl object-contain"/>:null}<strong>{content.branding?.brand_name||content.organization.name}</strong></div></header>:null}
    {sections.map((section) => {
      const c = section.content ?? {};
      if (section.type === "hero") return <section key={section.id} className="border-b border-black/5 bg-white">
        <div className="container-shell grid items-center gap-8 py-14 sm:py-20 lg:grid-cols-[1.15fr_.85fr]">
          <div><p className="text-sm font-bold uppercase tracking-widest" style={{ color: accent }}>{content.organization.segment ?? "Empresa"}</p><h1 className="mt-3 text-4xl font-black tracking-tight sm:text-5xl">{text(c.title, content.site?.headline || content.organization.name)}</h1><p className="muted mt-5 max-w-2xl text-lg leading-8">{text(c.subtitle, content.site?.subheadline || "Conheça nossos produtos e serviços.")}</p><a href={targetHref(c.cta_target, content.organization.whatsapp, content.organization.slug)} className="btn-primary mt-7" style={{ backgroundColor: accent }}>{text(c.cta_label, "Solicitar orçamento")}</a></div>
          {content.site?.cover_image_url ? <img src={content.site.cover_image_url} alt="" className="h-64 w-full rounded-3xl object-cover shadow-xl sm:h-80" /> : <div className="grid h-64 place-items-center rounded-3xl border border-dashed border-black/10 bg-black/[.025] text-center"><p className="muted max-w-xs text-sm">Adicione uma imagem de capa no editor para valorizar esta apresentação.</p></div>}
        </div>
      </section>;
      if (section.type === "about" && text(c.text, content.site?.about || "")) return <section key={section.id} className="container-shell py-12"><h2 className="text-2xl font-black">{text(c.title,"Sobre")}</h2><p className="muted mt-3 max-w-3xl whitespace-pre-line leading-7">{text(c.text,content.site?.about || "")}</p></section>;
      if (section.type === "services" && content.services.length) return <section key={section.id} className="container-shell py-12"><h2 className="text-2xl font-black">{text(c.title,"Serviços")}</h2><div className="mt-5 grid gap-4 md:grid-cols-2">{content.services.map((service) => <article key={service.id} className="card overflow-hidden">{service.image_url ? <img src={service.image_url} alt={service.name} className="h-44 w-full object-cover" /> : null}<div className="p-5"><h3 className="font-bold">{service.name}</h3>{service.description ? <p className="muted mt-2">{service.description}</p> : null}{money(service.starting_price_cents) ? <p className="mt-3 text-sm font-semibold">A partir de {money(service.starting_price_cents)}</p> : null}</div></article>)}</div></section>;
      if (section.type === "products" && content.products.length) return <section key={section.id} className="container-shell py-12"><h2 className="text-2xl font-black">{text(c.title,"Produtos")}</h2><div className="mt-5 grid gap-4 md:grid-cols-2">{content.products.map((product) => <article key={product.id} className="card overflow-hidden">{product.image_url ? <img src={product.image_url} alt={product.name} className="h-44 w-full object-cover" /> : null}<div className="p-5"><h3 className="font-bold">{product.name}</h3>{product.description ? <p className="muted mt-2">{product.description}</p> : null}{money(product.promotional_price_cents ?? product.price_cents) ? <p className="mt-3 text-sm font-semibold">{money(product.promotional_price_cents ?? product.price_cents)}</p> : null}</div></article>)}</div></section>;
      if (section.type === "contact") return <section key={section.id} id="contato" className="border-y border-black/5 bg-white"><div className="container-shell py-12"><h2 className="text-2xl font-black">{text(c.title,"Contato")}</h2><p className="muted mt-2">{text(c.text,"Fale com nossa equipe.")}</p><div className="mt-5 flex flex-wrap gap-3 text-sm">{content.organization.whatsapp ? <a className="btn-secondary" href={`https://wa.me/${content.organization.whatsapp.replace(/\D/g,"")}`}>WhatsApp</a> : null}{content.organization.phone ? <a className="btn-secondary" href={`tel:${content.organization.phone}`}>{content.organization.phone}</a> : null}{content.organization.city ? <span className="rounded-xl border border-black/10 px-4 py-3 font-semibold">{content.organization.city}{content.organization.state ? `/${content.organization.state}` : ""}</span> : null}{content.organization.latitude != null && content.organization.longitude != null ? <a className="btn-secondary" target="_blank" rel="noreferrer" href={`https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(`${content.organization.latitude},${content.organization.longitude}`)}`}>Ver no Google Maps</a> : content.organization.address ? <a className="btn-secondary" target="_blank" rel="noreferrer" href={`https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(content.organization.address)}`}>Ver localização</a> : null}</div></div></section>;
      if (section.type === "cta") return <section key={section.id} className="container-shell py-12"><div className="rounded-3xl p-7 text-white sm:p-10" style={{ backgroundColor: accent }}><h2 className="text-3xl font-black">{text(c.title,"Pronto para conversar?")}</h2><p className="mt-3 max-w-2xl text-white/85">{text(c.text,"Conte o que você precisa e fale com nossa equipe.")}</p><a href={targetHref(c.target,content.organization.whatsapp,content.organization.slug)} className="mt-6 inline-flex min-h-11 items-center justify-center rounded-xl bg-white px-5 font-bold text-black">{text(c.label,"Solicitar orçamento")}</a></div></section>;
      return null;
    })}

    {!preview && quoteAction ? <section id="orcamento" className="border-t border-black/5 bg-white py-14"><div className="container-shell grid gap-8 lg:grid-cols-[.8fr_1.2fr]"><div><h2 className="text-3xl font-black">Solicitar orçamento</h2><p className="muted mt-3">Envie sua necessidade. A solicitação será registrada no painel da empresa.</p>{quoteStatus === "recebido" ? <p className="mt-5 rounded-xl bg-emerald-50 p-4 text-sm font-semibold">Solicitação recebida com sucesso.</p> : quoteStatus === "limite" ? <p className="mt-5 rounded-xl bg-amber-50 p-4 text-sm">Muitas tentativas em pouco tempo. Tente novamente mais tarde.</p> : quoteStatus === "erro" ? <p className="mt-5 rounded-xl bg-amber-50 p-4 text-sm">Não foi possível enviar. Revise os campos e tente novamente.</p> : null}</div><form action={quoteAction} className="card grid gap-4 p-6"><label className="field"><span>Nome</span><input name="name" minLength={2} required /></label><div className="grid gap-4 sm:grid-cols-2"><label className="field"><span>WhatsApp</span><input name="whatsapp" inputMode="tel" /></label><label className="field"><span>E-mail</span><input name="email" type="email" /></label></div><label className="field"><span>O que você precisa?</span><textarea name="description" minLength={5} required /></label><label className="hidden" aria-hidden="true">Website<input name="website" tabIndex={-1} autoComplete="off" /></label><input type="hidden" name="utm_source" value={tracking.utm_source ?? ""}/><input type="hidden" name="utm_medium" value={tracking.utm_medium ?? ""}/><input type="hidden" name="utm_campaign" value={tracking.utm_campaign ?? ""}/><input type="hidden" name="utm_content" value={tracking.utm_content ?? ""}/><input type="hidden" name="utm_term" value={tracking.utm_term ?? ""}/><button className="btn-primary" type="submit" style={{ backgroundColor: accent }}>Enviar solicitação</button></form></div></section> : null}
  </main>;
}
