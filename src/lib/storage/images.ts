import "server-only";
import { randomUUID } from "node:crypto";
import { createClient } from "@/lib/supabase/server";

const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
const MIME_EXTENSIONS: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp"
};

export async function uploadOrganizationImage(input: {
  organizationId: string;
  folder: "catalog" | "site" | "profile";
  file: File;
}) {
  const extension = MIME_EXTENSIONS[input.file.type];
  if (!extension) throw new Error("Formato de imagem não permitido. Use JPG, PNG ou WebP.");
  if (input.file.size < 1 || input.file.size > MAX_IMAGE_BYTES) {
    throw new Error("A imagem deve ter no máximo 5 MB.");
  }

  const supabase = await createClient();
  const path = `${input.organizationId}/${input.folder}/${randomUUID()}.${extension}`;
  const { error } = await supabase.storage.from("organization-assets").upload(path, input.file, {
    cacheControl: "31536000",
    contentType: input.file.type,
    upsert: false
  });
  if (error) throw new Error(`Falha no upload: ${error.message}`);

  const { data } = supabase.storage.from("organization-assets").getPublicUrl(path);
  return { path, publicUrl: data.publicUrl };
}
