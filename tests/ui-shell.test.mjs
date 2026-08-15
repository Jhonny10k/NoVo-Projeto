import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");

test("dashboard navigation groups modules and provides a dedicated mobile menu", () => {
  const source = read("src/components/dashboard/nav.tsx");

  for (const group of ["Vendas", "Operação", "Crescimento", "Gestão"]) {
    assert.match(source, new RegExp(`label: \\"${group}\\"`));
  }

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
