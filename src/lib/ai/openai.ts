import "server-only";
import type {AIGenerateInput,AIGenerateResult,AIProvider} from "@/lib/ai/provider";

type OpenAIResponse={id?:string;model?:string;output?:Array<{type?:string;content?:Array<{type?:string;text?:string}>}>;usage?:{input_tokens?:number;output_tokens?:number;total_tokens?:number};error?:{message?:string;code?:string}};
function outputText(data:OpenAIResponse){return (data.output??[]).flatMap(item=>item.type==="message"?(item.content??[]):[]).filter(part=>part.type==="output_text"&&typeof part.text==="string").map(part=>part.text??"").join("\n").trim();}
function retryable(status:number){return status===429||[500,502,503,504].includes(status);}
export class OpenAIResponsesProvider implements AIProvider{
  name="openai";
  async generate(input:AIGenerateInput):Promise<AIGenerateResult>{
    const apiKey=process.env.OPENAI_API_KEY;if(!apiKey)throw new Error("AI_PROVIDER_NOT_CONFIGURED");
    const model=process.env.OPENAI_MODEL?.trim()||"gpt-5.6";
    let lastError="OPENAI_REQUEST_FAILED";
    for(let attempt=0;attempt<2;attempt++){
      try{
        const response=await fetch("https://api.openai.com/v1/responses",{method:"POST",headers:{authorization:`Bearer ${apiKey}`,"content-type":"application/json"},body:JSON.stringify({model,store:false,instructions:input.instructions,input:input.input,max_output_tokens:Math.min(Math.max(input.maxOutputTokens??700,100),1500)}),signal:AbortSignal.timeout(20000)});
        const data=await response.json() as OpenAIResponse;
        if(!response.ok){lastError=data.error?.code||`OPENAI_HTTP_${response.status}`;if(attempt===0&&retryable(response.status)){await new Promise(r=>setTimeout(r,450));continue;}throw new Error(lastError);}
        const text=outputText(data);if(!text)throw new Error("OPENAI_EMPTY_RESPONSE");
        return{text,provider:this.name,model:data.model||model,providerRequestId:data.id??null,inputTokens:data.usage?.input_tokens??0,outputTokens:data.usage?.output_tokens??0,totalTokens:data.usage?.total_tokens??((data.usage?.input_tokens??0)+(data.usage?.output_tokens??0))};
      }catch(error){lastError=error instanceof Error?error.message:"OPENAI_REQUEST_FAILED";if(attempt===0&&(lastError.includes("fetch")||lastError.includes("timeout"))){await new Promise(r=>setTimeout(r,450));continue;}throw error;}
    }
    throw new Error(lastError);
  }
}
