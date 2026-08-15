import type { MetadataRoute } from "next";
import { getPublicAppUrl } from "@/lib/env";
import { createClient } from "@/lib/supabase/server";

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const base = getPublicAppUrl();
  const staticPages: MetadataRoute.Sitemap = [
    { url:base, changeFrequency:"weekly", priority:1 },
    { url:`${base}/planos`, changeFrequency:"weekly", priority:.8 },
    { url:`${base}/contato`, changeFrequency:"monthly", priority:.6 },
    { url:`${base}/termos`, changeFrequency:"monthly", priority:.3 },
    { url:`${base}/privacidade`, changeFrequency:"monthly", priority:.3 }
  ];
  try {
    const supabase = await createClient();
    const { data } = await supabase.rpc("list_public_sites");
    const sites: MetadataRoute.Sitemap = (data ?? []).map((item: { slug:string; published_at:string|null }) => ({ url:`${base}/empresa/${item.slug}`, lastModified:item.published_at ? new Date(item.published_at) : undefined, changeFrequency:"weekly" as const, priority:.7 }));
    return [...staticPages,...sites];
  } catch { return staticPages; }
}
