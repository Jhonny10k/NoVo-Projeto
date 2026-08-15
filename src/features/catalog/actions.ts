"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { parseMoneyToCents } from "@/lib/format";
import { createClient } from "@/lib/supabase/server";
import { uploadOrganizationImage } from "@/lib/storage/images";

function field(formData: FormData, key: string, max = 2000) {
  const value = formData.get(key);
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function checked(formData: FormData, key: string) {
  return formData.get(key) === "on" || formData.get(key) === "true";
}

async function context() {
  const organization = await requireCurrentOrganization();
  return { organization, supabase: await createClient() };
}

async function categoryIdForTenant(supabase: Awaited<ReturnType<typeof createClient>>, organizationId: string, raw: string) {
  if (!raw) return null;
  const { data } = await supabase.from("categories").select("id").eq("organization_id", organizationId).eq("id", raw).maybeSingle();
  return data?.id ?? null;
}

export async function saveCategoryAction(formData: FormData) {
  const { organization, supabase } = await context();
  const id = field(formData, "id", 80);
  const name = field(formData, "name", 100);
  const sortRaw = Number(field(formData, "sort_order", 10));
  const sortOrder = Number.isInteger(sortRaw) ? Math.max(-10000, Math.min(10000, sortRaw)) : 0;
  if (!name) redirect("/catalogo?erro=categoria");

  const payload = { organization_id: organization.id, name, sort_order: sortOrder };
  const result = id
    ? await supabase.from("categories").update(payload).eq("organization_id", organization.id).eq("id", id)
    : await supabase.from("categories").insert(payload);
  if (result.error) redirect("/catalogo?erro=categoria");
  revalidatePath("/catalogo");
  redirect("/catalogo?status=categoria-salva");
}

export async function deleteCategoryAction(formData: FormData) {
  const { organization, supabase } = await context();
  const id = field(formData, "id", 80);
  if (!id) redirect("/catalogo?erro=categoria");
  const { error } = await supabase.from("categories").delete().eq("organization_id", organization.id).eq("id", id);
  if (error) redirect("/catalogo?erro=permissao");
  revalidatePath("/catalogo");
  redirect("/catalogo?status=categoria-excluida");
}

export async function saveProductAction(formData: FormData) {
  const { organization, supabase } = await context();
  const id = field(formData, "id", 80);
  const name = field(formData, "name", 160);
  const description = field(formData, "description", 3000);
  const priceCents = parseMoneyToCents(field(formData, "price", 40));
  const promotionalPriceCents = parseMoneyToCents(field(formData, "promotional_price", 40));
  const rawCategoryId = field(formData, "category_id", 80);
  const categoryId = await categoryIdForTenant(supabase, organization.id, rawCategoryId);
  if (rawCategoryId && !categoryId) redirect("/catalogo?erro=categoria");
  if (name.length < 2) redirect("/catalogo?erro=produto");

  const payload: Record<string, unknown> = {
    organization_id: organization.id,
    name,
    description: description || null,
    price_cents: priceCents,
    promotional_price_cents: promotionalPriceCents,
    category_id: categoryId,
    available: checked(formData, "available"),
    featured: checked(formData, "featured")
  };

  const image = formData.get("image");
  if (image instanceof File && image.size > 0) {
    try {
      const uploaded = await uploadOrganizationImage({ organizationId: organization.id, folder: "catalog", file: image });
      payload.image_url = uploaded.publicUrl;
    } catch {
      redirect("/catalogo?erro=imagem");
    }
  }

  const result = id
    ? await supabase.from("products").update(payload).eq("organization_id", organization.id).eq("id", id)
    : await supabase.from("products").insert(payload);

  if (result.error) redirect("/catalogo?erro=salvar");
  revalidatePath("/catalogo");
  revalidatePath(`/empresa/${organization.slug}`);
  redirect("/catalogo?status=produto-salvo");
}

export async function deleteProductAction(formData: FormData) {
  const { organization, supabase } = await context();
  const id = field(formData, "id", 80);
  if (!id) redirect("/catalogo?erro=produto");
  const { error } = await supabase.from("products").delete().eq("organization_id", organization.id).eq("id", id);
  if (error) redirect("/catalogo?erro=permissao");
  revalidatePath("/catalogo");
  redirect("/catalogo?status=produto-excluido");
}

export async function saveServiceAction(formData: FormData) {
  const { organization, supabase } = await context();
  const id = field(formData, "id", 80);
  const name = field(formData, "name", 160);
  const description = field(formData, "description", 3000);
  const startingPriceCents = parseMoneyToCents(field(formData, "starting_price", 40));
  const durationRaw = Number(field(formData, "duration_minutes", 10));
  const duration = Number.isInteger(durationRaw) && durationRaw > 0 ? durationRaw : null;
  const rawCategoryId = field(formData, "category_id", 80);
  const categoryId = await categoryIdForTenant(supabase, organization.id, rawCategoryId);
  if (rawCategoryId && !categoryId) redirect("/catalogo?erro=categoria");
  if (name.length < 2) redirect("/catalogo?erro=servico");

  const payload: Record<string, unknown> = {
    organization_id: organization.id,
    name,
    description: description || null,
    starting_price_cents: startingPriceCents,
    duration_minutes: duration,
    category_id: categoryId,
    active: checked(formData, "active")
  };

  const image = formData.get("image");
  if (image instanceof File && image.size > 0) {
    try {
      const uploaded = await uploadOrganizationImage({ organizationId: organization.id, folder: "catalog", file: image });
      payload.image_url = uploaded.publicUrl;
    } catch {
      redirect("/catalogo?erro=imagem");
    }
  }

  const result = id
    ? await supabase.from("services").update(payload).eq("organization_id", organization.id).eq("id", id)
    : await supabase.from("services").insert(payload);

  if (result.error) redirect("/catalogo?erro=salvar");
  revalidatePath("/catalogo");
  revalidatePath(`/empresa/${organization.slug}`);
  redirect("/catalogo?status=servico-salvo");
}

export async function deleteServiceAction(formData: FormData) {
  const { organization, supabase } = await context();
  const id = field(formData, "id", 80);
  if (!id) redirect("/catalogo?erro=servico");
  const { error } = await supabase.from("services").delete().eq("organization_id", organization.id).eq("id", id);
  if (error) redirect("/catalogo?erro=permissao");
  revalidatePath("/catalogo");
  redirect("/catalogo?status=servico-excluido");
}
