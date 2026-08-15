import type { Metadata } from "next";
import { headers } from "next/headers";
import { notFound } from "next/navigation";
import { SiteRenderer, type SiteRenderData } from "@/components/site/site-renderer";
import { VisitTracker } from "@/components/analytics/visit-tracker";
import { submitQuoteRequestAction } from "@/features/public-site/actions";
import { getPublicAppUrl } from "@/lib/env";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";
type Props = { params: Promise<{ slug: string }>; searchParams: Promise<Record<string,string|string[]|undefined>> };
type Branding={brand_name?:string|null;logo_url?:string|null;favicon_url?:string|null;primary_color?:string|null;hide_platform_branding?:boolean;primary_domain?:string|null};

async function loadSite(slug: string) {
  const supabase = await createClient();
  const [{data,error},{data:brandData}]=await Promise.all([supabase.rpc("get_public_site", { p_slug: slug }),supabase.rpc("get_public_branding",{p_slug:slug})]);
  if(error||!data)return null;const content=data as SiteRenderData;content.branding=(brandData||{}) as Branding;return content;
}
function publicUrl(content:SiteRenderData){const domain=content.branding?.primary_domain;return domain?`https://${domain}`:`${getPublicAppUrl()}/empresa/${content.organization.slug}`;}

export async function generateMetadata({ params }: Pick<Props,"params">): Promise<Metadata> {
  const { slug } = await params;const content=await loadSite(slug);
  if (!content) return { title:"Empresa não encontrada", robots:{ index:false, follow:false } };
  const title = content.site?.headline || content.branding?.brand_name || content.organization.name;
  const description = content.site?.subheadline || `Conheça ${content.branding?.brand_name||content.organization.name}, seus produtos e serviços.`;
  const url=publicUrl(content);const image=content.site?.cover_image_url||undefined;
  return { title,description,alternates:{canonical:url},icons:content.branding?.favicon_url?{icon:content.branding.favicon_url}:undefined,openGraph:{title,description,url,type:"website",images:image?[{url:image}]:undefined} };
}

export default async function PublicCompanyPage({ params, searchParams }: Props) {
  const { slug }=await params;const query=await searchParams;const content=await loadSite(slug);if(!content){notFound();throw new Error("Site não encontrado");}
  const requestHeaders=await headers();const requestHost=(requestHeaders.get("x-forwarded-host")||requestHeaders.get("host")||"").split(":")[0].toLowerCase();
  if(content.branding?.primary_domain&&requestHost&&requestHost!==content.branding.primary_domain&&requestHost!==new URL(getPublicAppUrl()).hostname.toLowerCase()){
    // O host pode ser um domínio secundário verificado. Não redirecionamos automaticamente para preservar links/campanhas.
  }
  const quoteStatus=typeof query.orcamento==="string"?query.orcamento:"";const q=(key:string,max:number)=>typeof query[key]==="string"?String(query[key]).slice(0,max):"";
  const tracking={utm_source:q("utm_source",120),utm_medium:q("utm_medium",120),utm_campaign:q("utm_campaign",160),utm_content:q("utm_content",160),utm_term:q("utm_term",160)};
  const url=content.branding?.primary_domain?`https://${content.branding.primary_domain}`:requestHost&&requestHost!==new URL(getPublicAppUrl()).hostname.toLowerCase()?`https://${requestHost}`:publicUrl(content);
  const publicName=content.branding?.brand_name||content.organization.name;
  const jsonLd={"@context":"https://schema.org","@type":"LocalBusiness",name:publicName,url,telephone:content.organization.phone||content.organization.whatsapp||undefined,address:(content.organization.address||content.organization.city)?{"@type":"PostalAddress",streetAddress:content.organization.address||undefined,addressLocality:content.organization.city||undefined,addressRegion:content.organization.state||undefined,addressCountry:"BR"}:undefined,geo:content.organization.latitude!=null&&content.organization.longitude!=null?{"@type":"GeoCoordinates",latitude:content.organization.latitude,longitude:content.organization.longitude}:undefined};
  return <><script type="application/ld+json" dangerouslySetInnerHTML={{__html:JSON.stringify(jsonLd).replace(/</g,"\\u003c")}}/><VisitTracker slug={content.organization.slug} tracking={tracking}/><SiteRenderer content={content} tracking={tracking} quoteStatus={quoteStatus} quoteAction={submitQuoteRequestAction.bind(null,slug)}/></>;
}
