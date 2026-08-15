import type { MetadataRoute } from "next";
import { getPublicAppUrl } from "@/lib/env";
export default function robots(): MetadataRoute.Robots { const baseUrl=getPublicAppUrl(); return { rules:[{userAgent:"*",allow:"/",disallow:["/dashboard","/onboarding","/crm","/clientes","/orcamentos","/tarefas","/catalogo","/site","/notificacoes","/equipe","/assinatura","/admin","/api/","/login","/cadastro","/esqueci-senha","/redefinir-senha","/definir-senha"]}], sitemap:`${baseUrl}/sitemap.xml` }; }
