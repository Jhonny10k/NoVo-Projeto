import { NextRequest,NextResponse } from "next/server";
import { timingSafeEqual } from "node:crypto";
import { processExternalOutbox } from "@/lib/outbox/worker";

export const runtime="nodejs";
export const dynamic="force-dynamic";

function authorized(request:NextRequest){
  const secret=process.env.OUTBOX_WORKER_SECRET;if(!secret)return false;
  const provided=request.headers.get("authorization")?.replace(/^Bearer\s+/i,"")||"";
  const a=Buffer.from(provided);const b=Buffer.from(secret);return a.length===b.length&&a.length>0&&timingSafeEqual(a,b);
}

export async function POST(request:NextRequest){
  if(!process.env.OUTBOX_WORKER_SECRET)return NextResponse.json({error:"worker_not_configured"},{status:503});
  if(!authorized(request))return NextResponse.json({error:"unauthorized"},{status:401});
  const rawLimit=Number(request.nextUrl.searchParams.get("limit")||20);const limit=Number.isFinite(rawLimit)?Math.trunc(rawLimit):20;
  try{return NextResponse.json(await processExternalOutbox(limit));}
  catch(error){return NextResponse.json({error:error instanceof Error?error.message:"outbox_failed"},{status:500});}
}
