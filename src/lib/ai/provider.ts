import "server-only";

export type AIGenerateInput={instructions:string;input:string;maxOutputTokens?:number};
export type AIGenerateResult={text:string;provider:string;model:string;providerRequestId:string|null;inputTokens:number;outputTokens:number;totalTokens:number};
export interface AIProvider{name:string;generate(input:AIGenerateInput):Promise<AIGenerateResult>}
