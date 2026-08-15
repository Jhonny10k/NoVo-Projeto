import { NextResponse } from "next/server";
import { publicApiOpenApiDocument } from "@/lib/public-api/openapi";

export const dynamic="force-static";

export async function GET(){
  return NextResponse.json(publicApiOpenApiDocument,{headers:{"Cache-Control":"public, max-age=300, s-maxage=3600","X-Content-Type-Options":"nosniff"}});
}
