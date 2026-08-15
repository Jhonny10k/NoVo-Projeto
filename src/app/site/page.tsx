import Link from "next/link";
import { DashboardNav } from "@/components/dashboard/nav";
import { DevicePreview } from "@/components/site/device-preview";
import { applySiteTemplateAction, moveSiteSectionAction, publishSiteAction, saveSiteSectionAction, saveSiteSettingsAction } from "@/features/site/actions";
import { requireUser } from "@/lib/auth/require-user";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { hasFeature, requireFeature } from "@/lib/plans/entitlements";
import { createClient } from "@/lib/supabase/server";
import { siteTemplates } from "@/lib/site/templates";

export const dynamic = "force-dynamic";
type Props = { searchParams: Promise<Record<string,string|string[]|undefined>> };
type Section = { id: string; section_type: string; enabled: boolean; sort_order: number; content: Record<string,unknown> };

const labels: Record<string,string> = { hero:"Hero", about:"Sobre", services:"Serviços", products:"Produtos", contact:"Contato", cta:"Chamada final" };
function contentText(content: Record<string,unknown>, key: string) { return typeof content[key] === "string" ? content[key] as string : ""; }

function SectionFields({ section }: { section: Section }) {
  const c = section.content ?? {};
  if (section.section_type === "hero") return <><label className="field"><span>Título</span><input name="title" maxLength={180} defaultValue={contentText(c,"title")} required /></label><label className="field"><span>Subtítulo</span><textarea name="subtitle" maxLength={320} defaultValue={contentText(c,"subtitle")} /></label><div className="grid gap-3 sm:grid-cols-2"><label className="field"><span>Texto do botão</span><input name="cta_label" maxLength={80} defaultValue={contentText(c,"cta_label")} /></label><label className="field"><span>Destino</span><select name="cta_target" defaultValue={contentText(c,"cta_target") || "quote"}><option value="quote">Orçamento</option><option value="whatsapp">WhatsApp</option><option value="contact">Contato</option><option value="booking">Agendar</option></select></label></div></>;
  if (section.section_type === "about") return <><label className="field"><span>Título</span><input name="title" maxLength={100} defaultValue={contentText(c,"title")} /></label><label className="field"><span>Texto</span><textarea name="text" maxLength={3000} defaultValue={contentText(c,"text")} /></label></>;
  if (section.section_type === "services" || section.section_type === "products") return <label className="field"><span>Título da seção</span><input name="title" maxLength={100} defaultValue={contentText(c,"title")} /></label>;
  if (section.section_type === "contact") return <><label className="field"><span>Título</span><input name="title" maxLength={100} defaultValue={contentText(c,"title")} /></label><label className="field"><span>Texto</span><textarea name="text" maxLength={600} defaultValue={contentText(c,"text")} /></label></>;
  if (section.section_type === "cta") return <><label className="field"><span>Título</span><input name="title" maxLength={180} defaultValue={contentText(c,"title")} /></label><label className="field"><span>Texto</span><textarea name="text" maxLength={600} defaultValue={contentText(c,"text")} /></label><div className="grid gap-3 sm:grid-cols-2"><label className="field"><span>Botão</span><input name="label" maxLength={80} defaultValue={contentText(c,"label")} /></label><label className="field"><span>Destino</span><select name="target" defaultValue={contentText(c,"target") || "quote"}><option value="quote">Orçamento</option><option value="whatsapp">WhatsApp</option><option value="contact">Contato</option><option value="booking">Agendar</option></select></label></div></>;
  return <p className="muted text-sm">Este bloco ainda não possui campos editáveis nesta versão.</p>;
}

export default async function SitePage({ searchParams }: Props) {
  await requireUser();
  await requireFeature("site");
  const organization = await requireCurrentOrganization();
  const advancedSite = await hasFeature("advanced_site");
  const supabase = await createClient();
  const [{ data: site }, { data: sections }] = await Promise.all([
    supabase.from("site_configs").select("status,published_at,version,primary_color,cover_image_url").eq("organization_id",organization.id).single(),
    supabase.from("site_sections").select("id,section_type,enabled,sort_order,content").eq("organization_id",organization.id).order("sort_order")
  ]);
  const params = await searchParams;
  const status = typeof params.status === "string" ? params.status : "";
  const error = typeof params.erro === "string" ? params.erro : "";
  const blocks = (sections ?? []) as Section[];

  return <><DashboardNav organizationName={organization.name} /><main className="container-shell py-10">
    <div className="flex flex-wrap items-end justify-between gap-4"><div><p className="text-sm font-bold uppercase tracking-widest text-blue-700">Editor do site</p><h1 className="mt-1 text-3xl font-black">Rascunho por blocos</h1><p className="muted mt-2">Ative, edite e reorganize os blocos. O site público só muda quando você publicar.</p></div><div className="flex flex-wrap gap-2">{site?.status === "published" ? <Link href={`/empresa/${organization.slug}`} className="btn-secondary">Ver versão publicada</Link> : null}<form action={publishSiteAction}><button className="btn-primary" type="submit">Publicar alterações</button></form></div></div>
    {status ? <p className="mt-5 rounded-xl bg-emerald-50 p-4 text-sm font-semibold">{status === "publicado" ? `Site publicado. Versão ${Number(site?.version ?? 1)} disponível aos clientes.` : "Rascunho atualizado com sucesso."}</p> : null}
    {error ? <p role="alert" className="mt-5 rounded-xl bg-amber-50 p-4 text-sm">Não foi possível concluir a alteração. Revise os dados e tente novamente.</p> : null}

    <section className="mt-7"><div><h2 className="text-xl font-black">Começar por um template</h2><p className="muted mt-1 text-sm">O template altera somente o rascunho. Revise no preview antes de publicar.</p></div><div className="mt-4 grid gap-4 md:grid-cols-2 xl:grid-cols-5">{siteTemplates.map(template=><article key={template.key} className="card flex flex-col p-5"><h3 className="font-black">{template.name}</h3><p className="muted mt-2 flex-1 text-sm">{template.description}</p><form action={applySiteTemplateAction} className="mt-4"><input type="hidden" name="template" value={template.key}/><button className="btn-secondary w-full" type="submit">Aplicar ao rascunho</button></form></article>)}</div></section>

    <section className="card mt-7 p-6"><h2 className="text-xl font-black">Identidade visual</h2><p className="muted mt-1 text-sm">Cor e capa também ficam no rascunho até a próxima publicação.</p>{advancedSite ? <form action={saveSiteSettingsAction} className="mt-5 grid gap-4 sm:grid-cols-2"><label className="field"><span>Cor principal</span><input name="primary_color" type="color" defaultValue={site?.primary_color || "#2457d6"} /></label><label className="field"><span>Imagem de capa</span><input name="cover_image" type="file" accept="image/jpeg,image/png,image/webp" /></label>{site?.cover_image_url ? <img src={site.cover_image_url} alt="Capa atual do rascunho" className="h-36 w-full rounded-xl object-cover sm:col-span-2" /> : null}<button className="btn-secondary sm:col-span-2 sm:justify-self-start" type="submit">Salvar identidade</button></form> : <div className="mt-4 rounded-xl bg-blue-50 p-4 text-sm"><strong>Personalização avançada não incluída no plano atual.</strong><div className="mt-3"><Link href="/assinatura?recurso=advanced_site" className="btn-secondary">Ver planos</Link></div></div>}</section>

    <section className="mt-8"><div className="flex items-end justify-between gap-4"><div><h2 className="text-xl font-black">Blocos</h2><p className="muted mt-1 text-sm">Use as setas para mudar a ordem sem editar números manualmente.</p></div><span className="rounded-xl bg-black/5 px-3 py-2 text-xs font-bold">{blocks.length} blocos</span></div><div className="mt-4 grid gap-4">{blocks.map((section,index) => <article key={section.id} className="card p-5"><div className="flex flex-wrap items-center justify-between gap-3"><div><p className="text-xs font-bold uppercase tracking-wider text-blue-700">Bloco {index+1}</p><h3 className="mt-1 text-lg font-black">{labels[section.section_type] ?? section.section_type}</h3></div><div className="flex gap-2"><form action={moveSiteSectionAction}><input type="hidden" name="section_id" value={section.id} /><input type="hidden" name="direction" value="up" /><button className="btn-secondary min-h-10" type="submit" disabled={index===0}>↑</button></form><form action={moveSiteSectionAction}><input type="hidden" name="section_id" value={section.id} /><input type="hidden" name="direction" value="down" /><button className="btn-secondary min-h-10" type="submit" disabled={index===blocks.length-1}>↓</button></form></div></div><form action={saveSiteSectionAction} className="mt-4 grid gap-4"><input type="hidden" name="section_id" value={section.id} /><label className="text-sm font-semibold"><input type="checkbox" name="enabled" defaultChecked={section.enabled} /> Exibir este bloco</label><SectionFields section={section} /><button className="btn-secondary justify-self-start" type="submit">Salvar bloco</button></form></article>)}</div></section>

    <DevicePreview />
  </main></>;
}
