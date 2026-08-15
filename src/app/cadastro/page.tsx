import Link from "next/link";
import { signUpAction } from "@/features/auth/actions";

type SignUpPageProps = {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

const errors: Record<string, string> = {
  config: "O ambiente Supabase ainda não foi configurado.",
  campos: "Revise os campos. A senha precisa ter pelo menos 8 caracteres.",
  cadastro: "Não foi possível concluir o cadastro.",
  limite: "Muitas tentativas de cadastro. Aguarde antes de tentar novamente."
};

export default async function SignUpPage({ searchParams }: SignUpPageProps) {
  const params = await searchParams;
  const errorKey = typeof params.erro === "string" ? params.erro : "";
  const success = params.sucesso === "verifique-email";

  return (
    <main className="container-shell grid min-h-screen place-items-center py-10">
      <section className="card w-full max-w-md p-7">
        <Link href="/" className="text-sm font-semibold text-blue-700">← Voltar</Link>
        <h1 className="mt-4 text-3xl font-black">Criar conta</h1>
        <p className="muted mt-2">Comece configurando o acesso do proprietário.</p>
        {errors[errorKey] ? <p role="alert" className="mt-4 rounded-lg bg-amber-50 p-3 text-sm">{errors[errorKey]}</p> : null}
        {success ? <p className="mt-4 rounded-lg bg-emerald-50 p-3 text-sm">Cadastro recebido. Verifique seu e-mail para confirmar a conta.</p> : null}

        <form action={signUpAction} className="mt-6 grid gap-4">
          <label className="field">
            <span>Seu nome</span>
            <input name="name" autoComplete="name" minLength={2} required />
          </label>
          <label className="field">
            <span>E-mail</span>
            <input name="email" type="email" autoComplete="email" required />
          </label>
          <label className="field">
            <span>Senha</span>
            <input name="password" type="password" autoComplete="new-password" minLength={8} required />
          </label>
          <button className="btn-primary" type="submit">Criar conta</button>
        </form>
      </section>
    </main>
  );
}
