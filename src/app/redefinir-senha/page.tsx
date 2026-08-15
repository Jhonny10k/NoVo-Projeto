import Link from "next/link";
import { updateRecoveredPasswordAction } from "@/features/auth/actions";
import { createClient } from "@/lib/supabase/server";

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

export default async function ResetPasswordPage({ searchParams }: Props) {
  const supabase = await createClient();
  const { data } = await supabase.auth.getUser();
  const params = await searchParams;
  const error = typeof params.erro === "string" ? params.erro : "";

  if (!data.user) return <main className="container-shell grid min-h-screen place-items-center py-10"><section className="card w-full max-w-md p-7"><h1 className="text-3xl font-black">Link inválido ou expirado</h1><p className="muted mt-3">Solicite uma nova recuperação para continuar.</p><Link href="/esqueci-senha" className="btn-primary mt-6">Solicitar outro link</Link></section></main>;

  return <main className="container-shell grid min-h-screen place-items-center py-10">
    <section className="card w-full max-w-md p-7">
      <h1 className="text-3xl font-black">Definir nova senha</h1>
      <p className="muted mt-2">Use pelo menos 8 caracteres e não reutilize uma senha comprometida.</p>
      {error ? <p role="alert" className="mt-4 rounded-lg bg-amber-50 p-3 text-sm">Não foi possível alterar a senha. Confira os campos e tente novamente.</p> : null}
      <form action={updateRecoveredPasswordAction} className="mt-6 grid gap-4">
        <label className="field"><span>Nova senha</span><input name="password" type="password" autoComplete="new-password" minLength={8} required /></label>
        <label className="field"><span>Confirmar nova senha</span><input name="confirm_password" type="password" autoComplete="new-password" minLength={8} required /></label>
        <button className="btn-primary" type="submit">Alterar senha</button>
      </form>
    </section>
  </main>;
}
