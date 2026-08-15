import "server-only";
import type {AIProvider} from "@/lib/ai/provider";
import {OpenAIResponsesProvider} from "@/lib/ai/openai";
export function isAIConfigured(){return Boolean(process.env.OPENAI_API_KEY);}
export function getAIProvider():AIProvider{const provider=(process.env.AI_PROVIDER||"openai").toLowerCase();if(provider==="openai")return new OpenAIResponsesProvider();throw new Error("AI_PROVIDER_UNSUPPORTED");}
