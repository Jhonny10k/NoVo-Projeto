import { NextResponse } from "next/server";
import { PublicApiError, apiHeaders, logPublicApiRequest, type ApiContext } from "@/lib/public-api/auth";
import type { PublicApiScope } from "@/lib/public-api/keys";

type ApiResult={status?:number;body:unknown};

export async function runPublicApi(request:Request,scope:PublicApiScope,route:string,handler:(context:ApiContext)=>Promise<ApiResult>){
  const started=Date.now();let context:ApiContext|null=null;let status=500;
  try{
    const {authenticatePublicApi}=await import("@/lib/public-api/auth");context=await authenticatePublicApi(request,scope);
    const result=await handler(context);status=result.status??200;
    return NextResponse.json(result.body,{status,headers:apiHeaders(context)});
  }catch(error){
    if(error instanceof PublicApiError){status=error.status;return NextResponse.json({error:{code:error.code,message:error.message}},{status});}
    status=500;return NextResponse.json({error:{code:"internal_error",message:"Falha interna ao processar a solicitação."}},{status});
  }finally{
    if(context)await logPublicApiRequest(context,{scope,method:request.method,route,status,durationMs:Date.now()-started});
  }
}
