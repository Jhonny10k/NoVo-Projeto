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

function moneyInput(value: number | null) {
  return value == null ? "" : (value / 100).toFixed(2).replace(".", ",");
}

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
  const allProducts = (products ?? []) as Product[];
  const allServices = (services ?? []) as Service[];
  const categoryNames = new Map(allCategories.map((category) => [category.id, category.name]));

  return (
    <>
      <DashboardNav organizationName={organization.name} />
      <main className="container-shell pb-14 pt-7 sm:pt-10">
        <section className="max-w-3xl">
          <p className="eyebrow">Oferta</p>
          <h1 className="page-title mt-4">Catálogo</h1>
          <p className="muted mt-3 max-w-2xl leading-7">Organize produtos e serviços sem manter dezenas de formulários abertos na mesma tela. Edite somente o item que precisa.</p>
        </section>

        {status ? <p className="mt-5 rounded-xl border border-emerald-100 bg-emerald-50 p-4 text-sm font-semibold text-emerald-800">Alteração salva com sucesso.</p> : null}
        {error ? <p role="alert" className="mt-5 rounded-xl border border-amber-100 bg-amber-50 p-4 text-sm text-amber-900">Não foi possível concluir a alteração. Verifique os dados e suas permissões.</p> : null}

        <section className="mt-7 grid grid-cols-3 gap-3 sm:max-w-xl">
          <div className="soft-panel p-4"><p className="text-xs font-semibold text-slate-500">Produtos</p><p className="mt-1 text-2xl font-extrabold">{allProducts.length}</p></div>
          <div className="soft-panel p-4"><p className="text-xs font-semibold text-slate-500">Serviços</p><p className="mt-1 text-2xl font-extrabold">{allServices.length}</p></div>
          <div className="soft-panel p-4"><p className="text-xs font-semibold text-slate-500">Categorias</p><p className="mt-1 text-2xl font-extrabold">{allCategories.length}</p></div>
        </section>

        <section className="mt-6 grid gap-4 lg:grid-cols-[.9fr_1.1fr]">
          <details className="card overflow-hidden">
            <summary className="flex min-h-16 items-center justify-between gap-3 px-5 py-4 sm:px-6">
              <span><span className="block font-extrabold">Categorias</span><span className="muted mt-1 block text-xs font-medium">Organize a vitrine e o cadastro.</span></span>
              <span className="rounded-full bg-slate-100 px-2.5 py-1 text-xs font-extrabold text-slate-600">{allCategories.length}</span>
            </summary>
            <div className="border-t border-slate-100 px-5 pb-6 pt-5 sm:px-6">
              <form action={saveCategoryAction} className="soft-panel grid gap-3 p-3 sm:grid-cols-[1fr_90px_auto] sm:items-end">
                <label className="field"><span>Nova categoria</span><input name="name" maxLength={100} required /></label>
                <label className="field"><span>Ordem</span><input name="sort_order" type="number" defaultValue="0" /></label>
                <button className="btn-primary" type="submit">Adicionar</button>
              </form>
              <div className="mt-4 grid gap-2">
                {allCategories.map((category) => (
                  <form action={saveCategoryAction} key={category.id} className="grid gap-2 rounded-xl border border-slate-200 p-3 sm:grid-cols-[1fr_82px_auto] sm:items-center">
                    <input type="hidden" name="id" value={category.id} />
                    <label className="field"><span className="sr-only">Nome da categoria</span><input name="name" defaultValue={category.name} maxLength={100} required /></label>
                    <label className="field"><span className="sr-only">Ordem</span><input name="sort_order" type="number" defaultValue={category.sort_order} /></label>
                    <div className="flex gap-2"><button className="btn-secondary min-h-10 px-3" type="submit">Salvar</button>{canDelete ? <button className="btn-danger min-h-10 px-3" type="submit" formAction={deleteCategoryAction}>Excluir</button> : null}</div>
                  </form>
                ))}
                {allCategories.length === 0 ? <p className="muted py-3 text-center text-sm">Nenhuma categoria criada.</p> : null}
              </div>
            </div>
          </details>

          <div className="grid gap-4 sm:grid-cols-2">
            <details className="card overflow-hidden">
              <summary className="flex min-h-16 items-center justify-between gap-3 px-5 py-4">
                <span><span className="block font-extrabold">Novo produto</span><span className="muted mt-1 block text-xs">Item físico ou comercializável.</span></span><span className="text-blue-700" aria-hidden="true">＋</span>
              </summary>
              <form action={saveProductAction} className="grid gap-4 border-t border-slate-100 px-5 pb-5 pt-4">
                <label className="field"><span>Nome</span><input name="name" minLength={2} maxLength={160} required /></label>
                <label className="field"><span>Descrição</span><textarea name="description" maxLength={3000} /></label>
                <label className="field"><span>Categoria</span><select name="category_id"><option value="">Sem categoria</option>{allCategories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}</select></label>
                <label className="field"><span>Imagem</span><input name="image" type="file" accept="image/jpeg,image/png,image/webp" /></label>
                <div className="grid gap-3"><label className="field"><span>Preço (R$)</span><input name="price" inputMode="decimal" placeholder="149,90" /></label><label className="field"><span>Promocional</span><input name="promotional_price" inputMode="decimal" /></label></div>
                <div className="flex flex-wrap gap-4 text-sm"><label className="flex items-center gap-2"><input type="checkbox" name="available" defaultChecked />Disponível</label><label className="flex items-center gap-2"><input type="checkbox" name="featured" />Destaque</label></div>
                <button className="btn-primary" type="submit">Adicionar produto</button>
              </form>
            </details>

            <details className="card overflow-hidden">
              <summary className="flex min-h-16 items-center justify-between gap-3 px-5 py-4">
                <span><span className="block font-extrabold">Novo serviço</span><span className="muted mt-1 block text-xs">Serviço com preço e duração.</span></span><span className="text-blue-700" aria-hidden="true">＋</span>
              </summary>
              <form action={saveServiceAction} className="grid gap-4 border-t border-slate-100 px-5 pb-5 pt-4">
                <label className="field"><span>Nome</span><input name="name" minLength={2} maxLength={160} required /></label>
                <label className="field"><span>Descrição</span><textarea name="description" maxLength={3000} /></label>
                <label className="field"><span>Categoria</span><select name="category_id"><option value="">Sem categoria</option>{allCategories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}</select></label>
                <label className="field"><span>Imagem</span><input name="image" type="file" accept="image/jpeg,image/png,image/webp" /></label>
                <div className="grid gap-3"><label className="field"><span>Preço inicial (R$)</span><input name="starting_price" inputMode="decimal" /></label><label className="field"><span>Duração (min)</span><input name="duration_minutes" type="number" min="1" /></label></div>
                <label className="flex items-center gap-2 text-sm"><input type="checkbox" name="active" defaultChecked />Serviço ativo</label>
                <button className="btn-primary" type="submit">Adicionar serviço</button>
              </form>
            </details>
          </div>
        </section>

        <section className="mt-9" aria-labelledby="products-title">
          <div className="mb-4"><h2 id="products-title" className="text-xl font-extrabold tracking-tight">Produtos cadastrados</h2><p className="muted mt-1 text-sm">Toque em um produto para abrir a edição completa.</p></div>
          <div className="grid gap-3 md:grid-cols-2">
            {allProducts.map((product) => (
              <details key={product.id} className="card overflow-hidden">
                <summary className="flex items-center gap-3 p-4 sm:p-5">
                  {product.image_url ? <img src={product.image_url} alt="" className="h-12 w-12 shrink-0 rounded-xl border border-slate-100 object-cover" /> : <span className="grid h-12 w-12 shrink-0 place-items-center rounded-xl bg-slate-100 text-sm font-extrabold text-slate-400" aria-hidden="true">P</span>}
                  <span className="min-w-0 flex-1"><span className="block truncate font-extrabold">{product.name}</span><span className="muted mt-1 block truncate text-xs">{product.category_id ? categoryNames.get(product.category_id) ?? "Categoria" : "Sem categoria"} · {formatMoney(product.promotional_price_cents ?? product.price_cents)}</span></span>
                  <span className={`shrink-0 rounded-full px-2.5 py-1 text-[.68rem] font-extrabold ${product.available ? "bg-emerald-50 text-emerald-700" : "bg-slate-100 text-slate-500"}`}>{product.available ? "Disponível" : "Indisponível"}</span>
                </summary>
                <form action={saveProductAction} className="grid gap-4 border-t border-slate-100 px-4 pb-5 pt-4 sm:px-5">
                  <input type="hidden" name="id" value={product.id} />
                  <label className="field"><span>Nome</span><input name="name" defaultValue={product.name} required /></label>
                  <label className="field"><span>Descrição</span><textarea name="description" defaultValue={product.description ?? ""} /></label>
                  <label className="field"><span>Categoria</span><select name="category_id" defaultValue={product.category_id ?? ""}><option value="">Sem categoria</option>{allCategories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}</select></label>
                  {product.image_url ? <img src={product.image_url} alt="" className="h-40 w-full rounded-xl object-cover" /> : null}
                  <label className="field"><span>Trocar imagem</span><input name="image" type="file" accept="image/jpeg,image/png,image/webp" /></label>
                  <div className="grid gap-3 sm:grid-cols-2"><label className="field"><span>Preço</span><input name="price" defaultValue={moneyInput(product.price_cents)} /></label><label className="field"><span>Promocional</span><input name="promotional_price" defaultValue={moneyInput(product.promotional_price_cents)} /></label></div>
                  <div className="flex flex-wrap gap-4 text-sm"><label className="flex items-center gap-2"><input type="checkbox" name="available" defaultChecked={product.available} />Disponível</label><label className="flex items-center gap-2"><input type="checkbox" name="featured" defaultChecked={product.featured} />Destaque</label></div>
                  <div className="flex flex-col gap-2 sm:flex-row"><button className="btn-secondary" type="submit">Salvar alterações</button>{canDelete ? <button className="btn-danger" type="submit" formAction={deleteProductAction}>Excluir produto</button> : null}</div>
                </form>
              </details>
            ))}
            {allProducts.length === 0 ? <div className="card p-7 text-center md:col-span-2"><h3 className="font-extrabold">Nenhum produto cadastrado</h3><p className="muted mt-2 text-sm">Use “Novo produto” acima quando precisar adicionar o primeiro item.</p></div> : null}
          </div>
        </section>

        <section className="mt-9" aria-labelledby="services-title">
          <div className="mb-4"><h2 id="services-title" className="text-xl font-extrabold tracking-tight">Serviços cadastrados</h2><p className="muted mt-1 text-sm">A edição fica recolhida até você escolher um serviço.</p></div>
          <div className="grid gap-3 md:grid-cols-2">
            {allServices.map((service) => (
              <details key={service.id} className="card overflow-hidden">
                <summary className="flex items-center gap-3 p-4 sm:p-5">
                  {service.image_url ? <img src={service.image_url} alt="" className="h-12 w-12 shrink-0 rounded-xl border border-slate-100 object-cover" /> : <span className="grid h-12 w-12 shrink-0 place-items-center rounded-xl bg-slate-100 text-sm font-extrabold text-slate-400" aria-hidden="true">S</span>}
                  <span className="min-w-0 flex-1"><span className="block truncate font-extrabold">{service.name}</span><span className="muted mt-1 block truncate text-xs">{service.category_id ? categoryNames.get(service.category_id) ?? "Categoria" : "Sem categoria"} · {formatMoney(service.starting_price_cents)}{service.duration_minutes ? ` · ${service.duration_minutes} min` : ""}</span></span>
                  <span className={`shrink-0 rounded-full px-2.5 py-1 text-[.68rem] font-extrabold ${service.active ? "bg-emerald-50 text-emerald-700" : "bg-slate-100 text-slate-500"}`}>{service.active ? "Ativo" : "Inativo"}</span>
                </summary>
                <form action={saveServiceAction} className="grid gap-4 border-t border-slate-100 px-4 pb-5 pt-4 sm:px-5">
                  <input type="hidden" name="id" value={service.id} />
                  <label className="field"><span>Nome</span><input name="name" defaultValue={service.name} required /></label>
                  <label className="field"><span>Descrição</span><textarea name="description" defaultValue={service.description ?? ""} /></label>
                  <label className="field"><span>Categoria</span><select name="category_id" defaultValue={service.category_id ?? ""}><option value="">Sem categoria</option>{allCategories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}</select></label>
                  {service.image_url ? <img src={service.image_url} alt="" className="h-40 w-full rounded-xl object-cover" /> : null}
                  <label className="field"><span>Trocar imagem</span><input name="image" type="file" accept="image/jpeg,image/png,image/webp" /></label>
                  <div className="grid gap-3 sm:grid-cols-2"><label className="field"><span>Preço inicial</span><input name="starting_price" defaultValue={moneyInput(service.starting_price_cents)} /></label><label className="field"><span>Duração</span><input name="duration_minutes" type="number" min="1" defaultValue={service.duration_minutes ?? ""} /></label></div>
                  <label className="flex items-center gap-2 text-sm"><input type="checkbox" name="active" defaultChecked={service.active} />Serviço ativo</label>
                  <div className="flex flex-col gap-2 sm:flex-row"><button className="btn-secondary" type="submit">Salvar alterações</button>{canDelete ? <button className="btn-danger" type="submit" formAction={deleteServiceAction}>Excluir serviço</button> : null}</div>
                </form>
              </details>
            ))}
            {allServices.length === 0 ? <div className="card p-7 text-center md:col-span-2"><h3 className="font-extrabold">Nenhum serviço cadastrado</h3><p className="muted mt-2 text-sm">Use “Novo serviço” acima quando precisar cadastrar sua primeira oferta.</p></div> : null}
          </div>
        </section>
      </main>
    </>
  );
}
