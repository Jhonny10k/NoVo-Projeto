import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");

test("dashboard navigation groups modules and provides a dedicated mobile menu", () => {
  const source = read("src/components/dashboard/nav.tsx");
  for (const group of ["Vendas", "Operação", "Crescimento", "Gestão"]) assert.match(source, new RegExp(`label: \\"${group}\\"`));
  assert.match(source, /mobile-nav-panel/);
  assert.match(source, /Navegação mobile/);
  assert.doesNotMatch(source, /flex flex-wrap items-center gap-x-4 gap-y-2/);
});

test("global design system includes responsive shell and modern typography", () => {
  const source = read("src/app/globals.css");
  assert.match(source, /font-family: ui-sans-serif/);
  assert.match(source, /\.mobile-nav-panel/);
  assert.match(source, /@media \(max-width: 767px\)/);
  assert.match(source, /table \{ display: block; width: 100%; overflow-x: auto;/);
  assert.doesNotMatch(source, /font-family: Arial/);
});

test("marketing home uses the redesigned product presentation", () => {
  const source = read("src/app/page.tsx");
  assert.match(source, /marketing-hero/);
  assert.match(source, /product-preview/);
  assert.match(source, /Menos módulos soltos/);
});

test("dashboard prioritizes attention metrics and quick actions", () => {
  const source = read("src/app/dashboard/page.tsx");
  assert.match(source, /dashboard-hero/);
  assert.match(source, /metric-card/);
  assert.match(source, /quick-link/);
  assert.match(source, /O que merece sua atenção hoje/);
});

test("CRM uses a mobile-friendly snap Kanban instead of a fixed 1200px seven-column grid", () => {
  const source = read("src/app/crm/page.tsx");
  assert.match(source, /snap-x snap-mandatory overflow-x-auto/);
  assert.match(source, /w-\[82vw\].*snap-start/);
  assert.doesNotMatch(source, /min-w-\[1200px\]/);
});

test("atendimento separates filters from the message stream and keeps mobile cards compact", () => {
  const source = read("src/app/atendimento/page.tsx");
  assert.match(source, /lg:grid-cols-\[250px_1fr\]/);
  assert.match(source, /Aplicar filtros/);
  assert.match(source, /line-clamp-4/);
});

test("quotes split creation into steps and provide dedicated mobile history cards", () => {
  const source = read("src/app/orcamentos/page.tsx");
  assert.match(source, /1\. Para quem/);
  assert.match(source, /2\. Itens/);
  assert.match(source, /3\. Condições/);
  assert.match(source, /md:hidden/);
  assert.match(source, /hidden overflow-hidden md:block/);
});

test("agenda keeps creation and public availability in focused expandable panels", () => {
  const source = read("src/app/agenda/page.tsx");
  assert.match(source, /Novo agendamento interno/);
  assert.match(source, /Disponibilidade pública/);
  assert.match(source, /<details className="card overflow-hidden">/);
});

test("catalog keeps existing products and services collapsed until editing is requested", () => {
  const source = read("src/app/catalogo/page.tsx");
  assert.match(source, /Toque em um produto para abrir a edição completa/);
  assert.match(source, /A edição fica recolhida até você escolher um serviço/);
  assert.match(source, /<details key=\{product\.id\}/);
  assert.match(source, /<details key=\{service\.id\}/);
});
