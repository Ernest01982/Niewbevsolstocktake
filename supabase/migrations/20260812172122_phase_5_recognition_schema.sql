create type public.recognition_confidence_tier as enum (
  'HIGH',
  'MEDIUM',
  'LOW',
  'NO_MATCH'
);

create type public.recognition_selection_method as enum (
  'AUTO_PRESELECT',
  'CANDIDATE_CONFIRMATION',
  'MANUAL_SEARCH',
  'NO_SELECTION'
);

create type public.recognition_media_status as enum (
  'NOT_STORED',
  'PENDING',
  'DELETED',
  'FAILED'
);

alter table public.company_settings
  add column recognition_high_confidence numeric(5, 4) not null default 0.8500,
  add column recognition_medium_confidence numeric(5, 4) not null default 0.5500,
  add constraint company_settings_recognition_thresholds_check check (
    recognition_medium_confidence >= 0
    and recognition_high_confidence <= 1
    and recognition_medium_confidence < recognition_high_confidence
  );

comment on column public.company_settings.recognition_high_confidence is
  'Minimum provider confidence for a high-confidence product preselection.';
comment on column public.company_settings.recognition_medium_confidence is
  'Minimum provider confidence for the up-to-three candidate confirmation flow.';

create table public.recognition_events (
  id uuid primary key default gen_random_uuid(),
  idempotency_key uuid not null unique,
  company_id uuid not null references public.companies (id) on delete restrict,
  warehouse_id uuid not null,
  stock_take_id uuid not null,
  stock_taker_session_id uuid not null,
  user_id uuid not null,
  provider text not null check (length(btrim(provider)) between 1 and 100),
  model text not null check (length(btrim(model)) between 1 and 160),
  confidence numeric(5, 4) check (confidence between 0 and 1),
  confidence_tier public.recognition_confidence_tier not null,
  candidate_products jsonb not null default '[]'::jsonb
    check (jsonb_typeof(candidate_products) = 'array' and jsonb_array_length(candidate_products) <= 3),
  selected_product_id uuid,
  selection_method public.recognition_selection_method not null default 'NO_SELECTION',
  media_bucket text,
  media_path text check (media_path is null or length(media_path) between 1 and 500),
  media_expires_at timestamptz,
  media_status public.recognition_media_status not null default 'NOT_STORED',
  cleanup_attempts integer not null default 0 check (cleanup_attempts >= 0),
  next_cleanup_at timestamptz,
  last_cleanup_attempt_at timestamptz,
  cleanup_error text check (cleanup_error is null or length(cleanup_error) <= 1000),
  cleaned_at timestamptz,
  captured_at timestamptz not null,
  recognized_at timestamptz not null default now(),
  selected_at timestamptz,
  created_at timestamptz not null default now(),
  constraint recognition_events_stock_take_scope_fkey
    foreign key (stock_take_id, company_id, warehouse_id)
    references public.stock_takes (id, company_id, warehouse_id) on delete restrict,
  constraint recognition_events_session_scope_fkey
    foreign key (stock_taker_session_id, company_id, warehouse_id, stock_take_id)
    references public.stock_taker_sessions (id, company_id, warehouse_id, stock_take_id)
    on delete restrict,
  constraint recognition_events_company_user_fkey
    foreign key (company_id, user_id)
    references public.company_memberships (company_id, user_id) on delete restrict,
  constraint recognition_events_selected_product_fkey
    foreign key (selected_product_id, company_id)
    references public.products (id, company_id) on delete restrict,
  constraint recognition_events_id_scope_key
    unique (id, company_id, warehouse_id, stock_take_id),
  constraint recognition_events_selection_check check (
    (selected_product_id is null and selection_method = 'NO_SELECTION' and selected_at is null)
    or (selected_product_id is not null and selection_method <> 'NO_SELECTION' and selected_at is not null)
  ),
  constraint recognition_events_media_check check (
    (
      media_path is null and media_bucket is null and media_expires_at is null
      and media_status = 'NOT_STORED' and next_cleanup_at is null
      and last_cleanup_attempt_at is null and cleanup_error is null and cleaned_at is null
    )
    or (
      media_path is not null and media_bucket = 'recognition-media'
      and media_expires_at is not null
      and media_expires_at <= captured_at + interval '48 hours'
      and media_status in ('PENDING', 'FAILED')
      and next_cleanup_at is not null and cleaned_at is null
    )
    or (
      media_path is not null and media_bucket = 'recognition-media'
      and media_expires_at is not null and media_status = 'DELETED'
      and next_cleanup_at is null and cleanup_error is null and cleaned_at is not null
    )
  )
);

comment on table public.recognition_events is
  'Recognition telemetry only. Candidate/selection metadata is retained; recognition imagery is transient and is not an audit record.';
comment on column public.recognition_events.idempotency_key is
  'Client-generated identity for online recognition and durable offline manual-search event sync.';
comment on column public.recognition_events.media_expires_at is
  'Hard deletion deadline, never more than 48 hours after capture.';

create function private.protect_recognition_event_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'DELETE'
    or current_setting('app.recognition_event_mutation', true) is distinct from 'allowed' then
    raise exception 'recognition_events rows may only be changed by controlled operations.'
      using errcode = '55000';
  end if;
  return new;
end;
$$;

revoke all on function private.protect_recognition_event_mutation() from public;

create trigger recognition_events_protect_update_or_delete
before update or delete on public.recognition_events
for each row execute function private.protect_recognition_event_mutation();

create index recognition_events_company_id_idx on public.recognition_events (company_id);
create index recognition_events_warehouse_id_idx on public.recognition_events (warehouse_id);
create index recognition_events_stock_take_id_idx on public.recognition_events (stock_take_id);
create index recognition_events_user_id_idx on public.recognition_events (user_id);
create index recognition_events_selected_product_id_idx on public.recognition_events (selected_product_id);
create index recognition_events_session_scope_idx
  on public.recognition_events (stock_taker_session_id, company_id, warehouse_id, stock_take_id);
create index recognition_events_stock_take_scope_idx
  on public.recognition_events (stock_take_id, company_id, warehouse_id);
create index recognition_events_company_user_idx
  on public.recognition_events (company_id, user_id);
create index recognition_events_selected_product_company_idx
  on public.recognition_events (selected_product_id, company_id);
create index recognition_events_cleanup_due_idx
  on public.recognition_events (next_cleanup_at, created_at)
  where media_status in ('PENDING', 'FAILED');
create index recognition_events_created_at_idx on public.recognition_events (created_at desc);

alter table public.recognition_events enable row level security;
alter table public.recognition_events force row level security;
