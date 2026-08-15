"use client";
import { useMemo, useState } from "react";
import type { CommunicationTemplate } from "@/lib/communications/templates";

export function EmailTemplateFields({templates}:{templates:CommunicationTemplate[]}){
  const initial=templates[0]??{code:"custom",label:"Personalizada",subject:"",body:""};const [selected,setSelected]=useState(initial.code);const [subject,setSubject]=useState(initial.subject||"");const [body,setBody]=useState(initial.body);const byCode=useMemo(()=>new Map(templates.map(t=>[t.code,t])),[templates]);
  return <><label className="field"><span>Modelo</span><select value={selected} onChange={e=>{const code=e.target.value;setSelected(code);const next=byCode.get(code);if(next){setSubject(next.subject||"");setBody(next.body);}}}><option value="custom">Personalizada</option>{templates.map(t=><option key={t.code} value={t.code}>{t.label}</option>)}</select><small className="muted">O modelo apenas preenche os campos. Revise antes de enviar.</small></label><label className="field"><span>Assunto</span><input name="subject" required maxLength={200} value={subject} onChange={e=>{setSubject(e.target.value);setSelected("custom");}}/></label><label className="field"><span>Mensagem</span><textarea name="body" required maxLength={10000} value={body} onChange={e=>{setBody(e.target.value);setSelected("custom");}}/></label></>;
}

export function WhatsAppTemplateFields({templates}:{templates:CommunicationTemplate[]}){
  const initial=templates[0]??{code:"custom",label:"Personalizada",body:""};const [selected,setSelected]=useState(initial.code);const [body,setBody]=useState(initial.body);const byCode=useMemo(()=>new Map(templates.map(t=>[t.code,t])),[templates]);
  return <><label className="field"><span>Mensagem pronta</span><select value={selected} onChange={e=>{const code=e.target.value;setSelected(code);const next=byCode.get(code);if(next)setBody(next.body);}}><option value="custom">Personalizada</option>{templates.map(t=><option key={t.code} value={t.code}>{t.label}</option>)}</select><small className="muted">O texto continua editável e só é enviado ao clicar no botão.</small></label><label className="field"><span>Mensagem livre</span><textarea name="body" required maxLength={4096} value={body} onChange={e=>{setBody(e.target.value);setSelected("custom");}}/></label></>;
}
