import Link from "next/link";
import { signInAction } from "@/features/auth/actions";

type LoginPageProps = {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

const messages: Record<string, string> = {
  config: "O ambiente Supabase ainda não foi configurado.",
  campos: "Preencha e-mail e senha.",
  credenciais: "Não foi possível entrar com essas credenciais.",
  limite: "Muitas tentativas de acesso. Aguarde um pouco antes de tentar novamente."
};

export default async function LoginPage({ searchParams }: LoginPageProps) {
  const params = await searchParams;
  const errorKey = typeof params.erro === "string" ? params.erro : "";
  const statusKey = typeof params.status === "string" ? params.status : "";
  const message = messages[errorKey];

  return (
    <main className="container-shell grid min-h-screen place-items-center py-10">
      <section className="card w-full max-w-md p-7">
        <Link href="/" className="text-sm font-semibold text-blue-700">← Voltar</Link>
        <h1 className="mt-4 text-3xl font-black">Entrar</h1>
        <p className="muted mt-2">Acesse o painel da sua empresa.</p>
        {message ? <p role="alert" className="mt-4 rounded-lg bg-amber-50 p-3 text-sm">{message}</p> : null}
        {statusKey === "senha-alterada" ? <p className="mt-4 rounded-lg bg-emerald-50 p-3 text-sm font-semibold">Senha alterada. Entre novamente com a nova senha.</p> : null}

        <form action={signInAction} className="mt-6 grid gap-4">
          <label className="field">
            <span>E-mail</span>
            <input name="email" type="email" autoComplete="email" required />
          </label>
          <label className="field">
            <span>Senha</span>
            <input name="password" type="password" autoComplete="current-password" minLength={8} required />
          </label>
          <div className="text-right"><Link href="/esqueci-senha" className="text-sm font-semibold text-blue-700">Esqueci minha senha</Link></div>
          <button className="btn-primary" type="submit">Entrar</button>
        </form>
        <p className="muted mt-5 text-sm">
          Ainda não possui conta? <Link href="/cadastro" className="font-bold text-blue-700">Criar conta</Link>
        </p>
      </section>
    </main>
  );
}
