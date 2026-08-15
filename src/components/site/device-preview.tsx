"use client";

import { useState } from "react";

type Device = "desktop" | "tablet" | "mobile";

export function DevicePreview() {
  const [device, setDevice] = useState<Device>("desktop");
  return <section className="mt-8">
    <div className="flex flex-wrap items-center justify-between gap-3"><div><h2 className="text-xl font-black">Preview do rascunho</h2><p className="muted mt-1 text-sm">Salve o bloco e confira a versão que ainda não foi publicada.</p></div><div className="flex gap-2">{(["desktop","tablet","mobile"] as Device[]).map((item) => <button key={item} type="button" onClick={() => setDevice(item)} className={device === item ? "btn-primary" : "btn-secondary"}>{item === "desktop" ? "Desktop" : item === "tablet" ? "Tablet" : "Celular"}</button>)}</div></div>
    <div className="mt-4 overflow-auto rounded-2xl border border-black/10 bg-black/[.03] p-4"><iframe title="Preview do site" src="/site/preview" className="mx-auto block min-h-[720px] bg-white shadow-xl transition-[width]" style={{ width: device === "desktop" ? "100%" : device === "tablet" ? "768px" : "390px", maxWidth: "100%" }} /></div>
  </section>;
}
