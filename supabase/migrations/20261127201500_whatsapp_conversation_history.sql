alter table public.whatsapp_inbox
  add column if not exists direction text not null default 'inbound'
    check (direction in ('inbound','outbound')),
  add column if not exists conversation_phone text;
update public.whatsapp_inbox
set conversation_phone = case when direction='inbound' then from_phone else to_phone end
where conversation_phone is null;
alter table public.whatsapp_inbox alter column conversation_phone set not null;
create index if not exists whatsapp_conversation_history_idx
  on public.whatsapp_inbox(conversation_phone,received_at desc);
