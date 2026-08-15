import { APP_NAME } from "@/lib/brand";
export const publicApiOpenApiDocument={
  openapi:"3.1.1",
  info:{
    title:`${APP_NAME} Public API`,
    version:"1.0.0",
    description:"API servidor-servidor para integrações autorizadas por organização. Use uma chave com o menor conjunto de escopos necessário."
  },
  servers:[{url:"/",description:"Mesmo host da aplicação"}],
  tags:[
    {name:"Leads",description:"Consulta e criação de leads."},
    {name:"Clientes",description:"Consulta de clientes."},
    {name:"Orçamentos",description:"Consulta de orçamentos."}
  ],
  paths:{
    "/api/v1/leads":{
      get:{
        tags:["Leads"],summary:"Listar leads",operationId:"listLeads",
        security:[{bearerAuth:[]}],"x-required-scope":"leads:read",
        parameters:[
          {$ref:"#/components/parameters/Limit"},
          {name:"after",in:"query",required:false,description:"Cursor ISO 8601 baseado em created_at.",schema:{type:"string",format:"date-time"}}
        ],
        responses:{
          "200":{description:"Leads do tenant autenticado.",headers:{"X-Request-Id":{$ref:"#/components/headers/RequestId"},"X-RateLimit-Limit":{$ref:"#/components/headers/RateLimitLimit"},"X-RateLimit-Remaining":{$ref:"#/components/headers/RateLimitRemaining"},"X-RateLimit-Reset":{$ref:"#/components/headers/RateLimitReset"}},content:{"application/json":{schema:{type:"object",required:["data","next_after"],properties:{data:{type:"array",items:{$ref:"#/components/schemas/Lead"}},next_after:{oneOf:[{type:"string",format:"date-time"},{type:"null"}]}}}}}},
          "401":{$ref:"#/components/responses/Unauthorized"},"403":{$ref:"#/components/responses/Forbidden"},"429":{$ref:"#/components/responses/RateLimited"},"500":{$ref:"#/components/responses/InternalError"}
        }
      },
      post:{
        tags:["Leads"],summary:"Criar lead",operationId:"createLead",
        security:[{bearerAuth:[]}],"x-required-scope":"leads:write",
        requestBody:{required:true,content:{"application/json":{schema:{$ref:"#/components/schemas/CreateLeadInput"}}}},
        responses:{
          "201":{description:"Lead criado.",content:{"application/json":{schema:{type:"object",required:["data"],properties:{data:{type:"object",required:["id"],properties:{id:{type:"string",format:"uuid"}}}}}}}},
          "400":{$ref:"#/components/responses/BadRequest"},"401":{$ref:"#/components/responses/Unauthorized"},"403":{$ref:"#/components/responses/Forbidden"},"422":{$ref:"#/components/responses/ValidationError"},"429":{$ref:"#/components/responses/RateLimited"},"500":{$ref:"#/components/responses/InternalError"}
        }
      }
    },
    "/api/v1/customers":{
      get:{
        tags:["Clientes"],summary:"Listar clientes",operationId:"listCustomers",
        security:[{bearerAuth:[]}],"x-required-scope":"customers:read",
        parameters:[{$ref:"#/components/parameters/Limit"},{name:"after",in:"query",required:false,schema:{type:"string",format:"date-time"}}],
        responses:{"200":{description:"Clientes do tenant autenticado.",content:{"application/json":{schema:{type:"object",required:["data","next_after"],properties:{data:{type:"array",items:{$ref:"#/components/schemas/Customer"}},next_after:{oneOf:[{type:"string",format:"date-time"},{type:"null"}]}}}}}},"401":{$ref:"#/components/responses/Unauthorized"},"403":{$ref:"#/components/responses/Forbidden"},"429":{$ref:"#/components/responses/RateLimited"},"500":{$ref:"#/components/responses/InternalError"}}
      }
    },
    "/api/v1/quotes":{
      get:{
        tags:["Orçamentos"],summary:"Listar orçamentos",operationId:"listQuotes",
        security:[{bearerAuth:[]}],"x-required-scope":"quotes:read",
        parameters:[{$ref:"#/components/parameters/Limit"},{name:"status",in:"query",required:false,schema:{type:"string",enum:["draft","sent","viewed","approved","rejected","change_requested","expired"]}}],
        responses:{"200":{description:"Orçamentos do tenant autenticado.",content:{"application/json":{schema:{type:"object",required:["data"],properties:{data:{type:"array",items:{$ref:"#/components/schemas/Quote"}}}}}}},"401":{$ref:"#/components/responses/Unauthorized"},"403":{$ref:"#/components/responses/Forbidden"},"429":{$ref:"#/components/responses/RateLimited"},"500":{$ref:"#/components/responses/InternalError"}}
      }
    }
  },
  components:{
    securitySchemes:{bearerAuth:{type:"http",scheme:"bearer",bearerFormat:"opaque API key",description:"Chave nd_live_... criada no painel Desenvolvedores."}},
    parameters:{Limit:{name:"limit",in:"query",required:false,description:"Máximo de registros por resposta.",schema:{type:"integer",minimum:1,maximum:100,default:50}}},
    headers:{
      RequestId:{description:"Identificador para rastrear a chamada sem registrar seu payload.",schema:{type:"string"}},
      RateLimitLimit:{description:"Quota horária da chave.",schema:{type:"integer"}},
      RateLimitRemaining:{description:"Requisições restantes na janela atual.",schema:{type:"integer"}},
      RateLimitReset:{description:"Fim da janela atual.",schema:{type:"string",format:"date-time"}}
    },
    schemas:{
      ApiError:{type:"object",required:["error"],properties:{error:{type:"object",required:["code","message"],properties:{code:{type:"string"},message:{type:"string"}}}}},
      Lead:{type:"object",required:["id","name","source","status","created_at"],properties:{id:{type:"string",format:"uuid"},name:{type:"string"},phone:{oneOf:[{type:"string"},{type:"null"}]},whatsapp:{oneOf:[{type:"string"},{type:"null"}]},email:{oneOf:[{type:"string",format:"email"},{type:"null"}]},company:{oneOf:[{type:"string"},{type:"null"}]},source:{type:"string"},status:{type:"string"},tags:{type:"array",items:{type:"string"}},potential_value_cents:{oneOf:[{type:"integer",minimum:0},{type:"null"}]},interest:{oneOf:[{type:"string"},{type:"null"}]},last_contact_at:{oneOf:[{type:"string",format:"date-time"},{type:"null"}]},next_contact_at:{oneOf:[{type:"string",format:"date-time"},{type:"null"}]},created_at:{type:"string",format:"date-time"},updated_at:{type:"string",format:"date-time"}}},
      CreateLeadInput:{type:"object",required:["name"],additionalProperties:false,properties:{name:{type:"string",minLength:2,maxLength:160},phone:{type:"string",maxLength:40},whatsapp:{type:"string",maxLength:40},email:{type:"string",format:"email",maxLength:254},company:{type:"string",maxLength:160},interest:{type:"string",maxLength:500},potential_value_cents:{type:"integer",minimum:0}}},
      Customer:{type:"object",required:["id","name","created_at"],properties:{id:{type:"string",format:"uuid"},source_lead_id:{oneOf:[{type:"string",format:"uuid"},{type:"null"}]},name:{type:"string"},phone:{oneOf:[{type:"string"},{type:"null"}]},whatsapp:{oneOf:[{type:"string"},{type:"null"}]},email:{oneOf:[{type:"string",format:"email"},{type:"null"}]},company:{oneOf:[{type:"string"},{type:"null"}]},created_at:{type:"string",format:"date-time"},updated_at:{type:"string",format:"date-time"}}},
      Quote:{type:"object",required:["id","number","status","subtotal_cents","discount_cents","fee_cents","total_cents","created_at"],properties:{id:{type:"string",format:"uuid"},number:{type:"integer"},lead_id:{oneOf:[{type:"string",format:"uuid"},{type:"null"}]},customer_id:{oneOf:[{type:"string",format:"uuid"},{type:"null"}]},status:{type:"string"},subtotal_cents:{type:"integer"},discount_cents:{type:"integer"},fee_cents:{type:"integer"},total_cents:{type:"integer"},valid_until:{oneOf:[{type:"string",format:"date"},{type:"null"}]},created_at:{type:"string",format:"date-time"},updated_at:{type:"string",format:"date-time"}}}
    },
    responses:{
      BadRequest:{description:"Requisição inválida.",content:{"application/json":{schema:{$ref:"#/components/schemas/ApiError"}}}},
      Unauthorized:{description:"Chave ausente, inválida, revogada ou expirada.",content:{"application/json":{schema:{$ref:"#/components/schemas/ApiError"}}}},
      Forbidden:{description:"Escopo ou recurso do plano insuficiente.",content:{"application/json":{schema:{$ref:"#/components/schemas/ApiError"}}}},
      ValidationError:{description:"Dados não passaram na validação.",content:{"application/json":{schema:{$ref:"#/components/schemas/ApiError"}}}},
      RateLimited:{description:"Quota horária excedida.",content:{"application/json":{schema:{$ref:"#/components/schemas/ApiError"}}}},
      InternalError:{description:"Falha interna sem detalhes sensíveis.",content:{"application/json":{schema:{$ref:"#/components/schemas/ApiError"}}}}
    }
  }
} as const;
