import type { Metadata } from "next";
import { MarketingHeader } from "@/components/marketing/header";
import { MarketingFooter } from "@/components/marketing/footer";
import { submitCommercialContactAction } from "@/features/contact/actions";

export const metadata: Metadata = { title:"Contato", description:"Fale com a equipe comercial sobre a plataforma para seu negócio." };
type Props = { searchParams: Promise<Record<string,string|string[]|undefined>> };

export default async function ContactPage({ searchParams }: Props) {
  const params = await searchParams;
  const status = typeof params.status === "string" ? params.status : "";
  const error = typeof params.erro === "string" ? params.erro : "";
  const supportEmail = process.env.SUPPORT_EMAIL?.trim() || "";
  const whatsapp = process.env.COMMERCIAL_WHATSAPP?.replace(/\D/g,"") || "";
  return <><MarketingHeader /><main className="container-shell py-14"><div className="grid gap-8 lg:grid-cols-[.8fr_1.2fr]"><section><p className="text-sm font-bold uppercase tracking-widest text-blue-700">Contato</p><h1 className="mt-2 text-4xl font-black">Vamos conversar sobre sua empresa</h1><p className="muted mt-4 leading-7">Envie sua necessidade. A mensagem será registrada para atendimento comercial — não simulamos chat ou resposta automática quando não há integração configurada.</p><div className="mt-6 flex flex-wrap gap-2">{supportEmail ? <a href={`mailto:${supportEmail}`} className="btn-secondary">{supportEmail}</a> : null}{whatsapp ? <a href={`https://wa.me/${whatsapp}`} className="btn-secondary">WhatsApp comercial</a> : null}</div></section><form action={submitCommercialContactAction} className="card grid gap-4 p-6"><h2 className="text-xl font-black">Enviar mensagem</h2>{status === "recebido" ? <p className="rounded-xl bg-emerald-50 p-4 text-sm font-semibold">Mensagem recebida. Nossa equipe poderá acompanhar o contato registrado.</p> : null}{error ? <p role="alert" className="rounded-xl bg-amber-50 p-4 text-sm">Não foi possível enviar agora. Revise os campos ou tente novamente mais tarde.</p> : null}<label className="field"><span>Nome</span><input name="name" minLength={2} maxLength={160} required /></label><div className="grid gap-4 sm:grid-cols-2"><label className="field"><span>E-mail</span><input name="email" type="email" maxLength={254} required /></label><label className="field"><span>Telefone/WhatsApp</span><input name="phone" inputMode="tel" maxLength={80} /></label></div><label className="field"><span>Como podemos ajudar?</span><textarea name="message" minLength={5} maxLength={5000} required /></label><label className="hidden" aria-hidden="true">Website<input name="website" tabIndex={-1} autoComplete="off" /></label><button className="btn-primary" type="submit">Enviar mensagem</button></form></div></main><MarketingFooter /></>;
}
