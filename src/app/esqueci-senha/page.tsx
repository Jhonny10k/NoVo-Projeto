import Link from "next/link";
import { requestPasswordResetAction } from "@/features/auth/actions";

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

const errors: Record<string, string> = {
  config: "O ambiente de autenticação ainda não foi configurado.",
  campos: "Informe um e-mail válido.",
  limite: "Muitas solicitações em pouco tempo. Tente novamente mais tarde.",
  sessao: "O link de recuperação expirou ou não é mais válido. Solicite outro."
};

export default async function ForgotPasswordPage({ searchParams }: Props) {
  const params = await searchParams;
  const errorKey = typeof params.erro === "string" ? params.erro : "";
  const status = typeof params.status === "string" ? params.status : "";

  return <main className="container-shell grid min-h-screen place-items-center py-10">
    <section className="card w-full max-w-md p-7">
      <Link href="/login" className="text-sm font-semibold text-blue-700">← Voltar ao login</Link>
      <h1 className="mt-4 text-3xl font-black">Recuperar senha</h1>
      <p className="muted mt-2">Informe seu e-mail. Se houver uma conta compatível, você receberá um link para criar uma nova senha.</p>
      {errors[errorKey] ? <p role="alert" className="mt-4 rounded-lg bg-amber-50 p-3 text-sm">{errors[errorKey]}</p> : null}
      {status === "enviado" ? <p className="mt-4 rounded-lg bg-emerald-50 p-3 text-sm font-semibold">Se o e-mail estiver cadastrado, as instruções de recuperação foram enviadas.</p> : null}
      <form action={requestPasswordResetAction} className="mt-6 grid gap-4">
        <label className="field"><span>E-mail</span><input type="email" name="email" autoComplete="email" required /></label>
        <button className="btn-primary" type="submit">Enviar link de recuperação</button>
      </form>
    </section>
  </main>;
}
