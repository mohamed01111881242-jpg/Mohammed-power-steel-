create table if not exists public.whatsapp_inbox (
  id uuid primary key default gen_random_uuid(),
  wa_message_id text not null unique,
  profile_id uuid references public.profiles(id) on delete set null,
  from_phone text not null,
  to_phone text,
  message_type text not null,
  body text,
  raw_payload jsonb not null default '{}'::jsonb,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  processing_status text not null default 'received' check (processing_status in ('received','processing','processed','failed')),
  created_at timestamptz not null default now()
);
create index if not exists whatsapp_inbox_phone_received_idx on public.whatsapp_inbox(from_phone,received_at desc);
create index if not exists whatsapp_inbox_status_idx on public.whatsapp_inbox(processing_status,received_at);
alter table public.whatsapp_inbox enable row level security;
revoke all on public.whatsapp_inbox from public,anon,authenticated;
