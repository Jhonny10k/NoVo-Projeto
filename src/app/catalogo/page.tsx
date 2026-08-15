import { DashboardNav } from "@/components/dashboard/nav";
import { deleteCategoryAction, deleteProductAction, deleteServiceAction, saveCategoryAction, saveProductAction, saveServiceAction } from "@/features/catalog/actions";
import { requireUser } from "@/lib/auth/require-user";
import { formatMoney } from "@/lib/format";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };
type Category = { id: string; name: string; sort_order: number };
type Product = { id: string; name: string; description: string | null; category_id: string | null; price_cents: number | null; promotional_price_cents: number | null; image_url: string | null; available: boolean; featured: boolean };
type Service = { id: string; name: string; description: string | null; category_id: string | null; starting_price_cents: number | null; duration_minutes: number | null; image_url: string | null; active: boolean };

export default async function CatalogPage({ searchParams }: Props) {
  await requireUser();
  const organization = await requireCurrentOrganization();
  const supabase = await createClient();
  const [{ data: categories }, { data: products }, { data: services }] = await Promise.all([
    supabase.from("categories").select("id,name,sort_order").eq("organization_id", organization.id).order("sort_order").order("name"),
    supabase.from("products").select("id,name,description,category_id,price_cents,promotional_price_cents,image_url,available,featured").eq("organization_id", organization.id).order("created_at", { ascending: false }),
    supabase.from("services").select("id,name,description,category_id,starting_price_cents,duration_minutes,image_url,active").eq("organization_id", organization.id).order("created_at", { ascending: false })
  ]);
  const params = await searchParams;
  const status = typeof params.status === "string" ? params.status : "";
  const error = typeof params.erro === "string" ? params.erro : "";
  const canDelete = ["owner", "admin"].includes(organization.role);
  const allCategories = (categories ?? []) as Category[];

  return <>
    <DashboardNav organizationName={organization.name} />
    <main className="container-shell py-10">
      <h1 className="text-3xl font-black">Produtos e serviços</h1>
      <p className="muted mt-2">Tudo que estiver ativo poderá aparecer no site público após a publicação do site.</p>
      {status ? <p className="mt-5 rounded-xl bg-emerald-50 p-4 text-sm font-semibold">Alteração salva com sucesso.</p> : null}
      {error ? <p role="alert" className="mt-5 rounded-xl bg-amber-50 p-4 text-sm">Não foi possível concluir a alteração. Verifique os dados e suas permissões.</p> : null}

      <section className="card mt-8 p-5">
        <div className="flex flex-wrap items-end justify-between gap-4"><div><h2 className="text-xl font-black">Categorias</h2><p className="muted mt-1 text-sm">Organize produtos e serviços sem misturar categorias entre empresas.</p></div><form action={saveCategoryAction} className="flex flex-wrap items-end gap-2"><label className="field"><span>Nova categoria</span><input name="name" maxLength={100} required /></label><label className="field w-24"><span>Ordem</span><input name="sort_order" type="number" defaultValue="0" /></label><button className="btn-primary" type="submit">Adicionar</button></form></div>
        <div className="mt-5 grid gap-2 sm:grid-cols-2 lg:grid-cols-3">{allCategories.map((category) => <form action={saveCategoryAction} key={category.id} className="rounded-xl border border-black/10 p-3"><input type="hidden" name="id" value={category.id} /><div className="grid grid-cols-[1fr_82px] gap-2"><input name="name" defaultValue={category.name} maxLength={100} required className="min-h-10 rounded-lg border border-black/10 px-3" /><input name="sort_order" type="number" defaultValue={category.sort_order} className="min-h-10 rounded-lg border border-black/10 px-2" /></div><div className="mt-2 flex gap-2"><button className="btn-secondary min-h-9" type="submit">Salvar</button>{canDelete ? <button className="btn-danger min-h-9" type="submit" formAction={deleteCategoryAction}>Excluir</button> : null}</div></form>)}{allCategories.length === 0 ? <p className="muted text-sm">Nenhuma categoria criada.</p> : null}</div>
      </section>

      <section className="mt-8 grid gap-6 lg:grid-cols-2">
        <div>
          <h2 className="text-xl font-black">Novo produto</h2>
          <form action={saveProductAction} className="card mt-4 grid gap-4 p-5">
            <label className="field"><span>Nome</span><input name="name" minLength={2} maxLength={160} required /></label>
            <label className="field"><span>Descrição</span><textarea name="description" maxLength={3000} /></label>
            <label className="field"><span>Categoria</span><select name="category_id"><option value="">Sem categoria</option>{allCategories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}</select></label>
            <label className="field"><span>Imagem</span><input name="image" type="file" accept="image/jpeg,image/png,image/webp" /></label>
            <div className="grid gap-4 sm:grid-cols-2">
              <label className="field"><span>Preço (R$)</span><input name="price" inputMode="decimal" placeholder="149,90" /></label>
              <label className="field"><span>Preço promocional</span><input name="promotional_price" inputMode="decimal" /></label>
            </div>
            <div className="flex flex-wrap gap-5 text-sm"><label><input type="checkbox" name="available" defaultChecked /> Disponível</label><label><input type="checkbox" name="featured" /> Destaque</label></div>
            <button className="btn-primary" type="submit">Adicionar produto</button>
          </form>
        </div>
        <div>
          <h2 className="text-xl font-black">Novo serviço</h2>
          <form action={saveServiceAction} className="card mt-4 grid gap-4 p-5">
            <label className="field"><span>Nome</span><input name="name" minLength={2} maxLength={160} required /></label>
            <label className="field"><span>Descrição</span><textarea name="description" maxLength={3000} /></label>
            <label className="field"><span>Categoria</span><select name="category_id"><option value="">Sem categoria</option>{allCategories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}</select></label>
            <label className="field"><span>Imagem</span><input name="image" type="file" accept="image/jpeg,image/png,image/webp" /></label>
            <div className="grid gap-4 sm:grid-cols-2">
              <label className="field"><span>Preço inicial (R$)</span><input name="starting_price" inputMode="decimal" /></label>
              <label className="field"><span>Duração (min)</span><input name="duration_minutes" type="number" min="1" /></label>
            </div>
            <label className="text-sm"><input type="checkbox" name="active" defaultChecked /> Serviço ativo</label>
            <button className="btn-primary" type="submit">Adicionar serviço</button>
          </form>
        </div>
      </section>

      <section className="mt-10">
        <h2 className="text-xl font-black">Produtos cadastrados</h2>
        <div className="mt-4 grid gap-4 md:grid-cols-2">
          {((products ?? []) as Product[]).map((product) => <form action={saveProductAction} key={product.id} className="card grid gap-3 p-5">
            <input type="hidden" name="id" value={product.id} />
            <label className="field"><span>Nome</span><input name="name" defaultValue={product.name} required /></label>
            <label className="field"><span>Descrição</span><textarea name="description" defaultValue={product.description ?? ""} /></label><label className="field"><span>Categoria</span><select name="category_id" defaultValue={product.category_id ?? ""}><option value="">Sem categoria</option>{allCategories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}</select></label>{product.image_url ? <img src={product.image_url} alt="" className="h-32 w-full rounded-xl object-cover" /> : null}<label className="field"><span>Trocar imagem</span><input name="image" type="file" accept="image/jpeg,image/png,image/webp" /></label>
            <div className="grid gap-3 sm:grid-cols-2"><label className="field"><span>Preço</span><input name="price" defaultValue={product.price_cents == null ? "" : (product.price_cents / 100).toFixed(2).replace(".", ",")} /></label><label className="field"><span>Promocional</span><input name="promotional_price" defaultValue={product.promotional_price_cents == null ? "" : (product.promotional_price_cents / 100).toFixed(2).replace(".", ",")} /></label></div>
            <p className="muted text-xs">Atual: {formatMoney(product.promotional_price_cents ?? product.price_cents)}</p>
            <div className="flex gap-4 text-sm"><label><input type="checkbox" name="available" defaultChecked={product.available} /> Disponível</label><label><input type="checkbox" name="featured" defaultChecked={product.featured} /> Destaque</label></div>
            <div className="flex flex-wrap gap-2"><button className="btn-secondary" type="submit">Salvar</button>{canDelete ? <button className="btn-danger" type="submit" formAction={deleteProductAction}>Excluir</button> : null}</div>
          </form>)}
          {(products ?? []).length === 0 ? <div className="card p-5"><p className="font-semibold">Nenhum produto cadastrado.</p></div> : null}
        </div>
      </section>

      <section className="mt-10">
        <h2 className="text-xl font-black">Serviços cadastrados</h2>
        <div className="mt-4 grid gap-4 md:grid-cols-2">
          {((services ?? []) as Service[]).map((service) => <form action={saveServiceAction} key={service.id} className="card grid gap-3 p-5">
            <input type="hidden" name="id" value={service.id} />
            <label className="field"><span>Nome</span><input name="name" defaultValue={service.name} required /></label>
            <label className="field"><span>Descrição</span><textarea name="description" defaultValue={service.description ?? ""} /></label><label className="field"><span>Categoria</span><select name="category_id" defaultValue={service.category_id ?? ""}><option value="">Sem categoria</option>{allCategories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}</select></label>{service.image_url ? <img src={service.image_url} alt="" className="h-32 w-full rounded-xl object-cover" /> : null}<label className="field"><span>Trocar imagem</span><input name="image" type="file" accept="image/jpeg,image/png,image/webp" /></label>
            <div className="grid gap-3 sm:grid-cols-2"><label className="field"><span>Preço inicial</span><input name="starting_price" defaultValue={service.starting_price_cents == null ? "" : (service.starting_price_cents / 100).toFixed(2).replace(".", ",")} /></label><label className="field"><span>Duração</span><input name="duration_minutes" type="number" min="1" defaultValue={service.duration_minutes ?? ""} /></label></div>
            <label className="text-sm"><input type="checkbox" name="active" defaultChecked={service.active} /> Ativo</label>
            <div className="flex flex-wrap gap-2"><button className="btn-secondary" type="submit">Salvar</button>{canDelete ? <button className="btn-danger" type="submit" formAction={deleteServiceAction}>Excluir</button> : null}</div>
          </form>)}
          {(services ?? []).length === 0 ? <div className="card p-5"><p className="font-semibold">Nenhum serviço cadastrado.</p></div> : null}
        </div>
      </section>
    </main>
  </>;
}
