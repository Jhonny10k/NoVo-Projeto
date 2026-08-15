import Link from "next/link";
import { APP_NAME } from "@/lib/brand";

export function MarketingFooter(){return <footer className="border-t border-black/5 bg-white"><div className="container-shell flex flex-wrap items-center justify-between gap-4 py-8 text-sm"><p className="muted">© {new Date().getFullYear()} {APP_NAME}</p><nav className="flex flex-wrap gap-4"><Link href="/contato">Contato</Link><Link href="/termos">Termos</Link><Link href="/privacidade">Privacidade</Link></nav></div></footer>}
