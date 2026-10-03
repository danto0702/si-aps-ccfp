-- CuentasBot — initial schema DRAFT (proposal, not yet a migration).
-- Target: Supabase Postgres 15+. Amounts in COP as bigint (no decimals).
-- Sensitive columns (*_enc) hold AES-256-GCM ciphertext produced by the app
-- ("v1:<iv>:<tag>:<ct>" base64); *_bidx columns hold HMAC-SHA256 blind indexes.

create extension if not exists pgcrypto;
create extension if not exists pgmq;
create extension if not exists pg_cron;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
create type staff_role as enum ('superadmin', 'operator');
create type user_status as enum ('onboarding', 'pending_templates', 'active', 'suspended', 'deleted');
create type contract_status as enum ('draft', 'active', 'finished', 'terminated');
create type period_kind as enum ('calendar', 'anniversary');
create type period_status as enum (
  'scheduled', 'collecting', 'ready_to_draft', 'draft_review',
  'approved', 'generating', 'delivered', 'blocked_payment'
);
create type obligation_kind as enum ('specific', 'general');
create type support_frequency as enum ('every_period', 'once', 'at_start');
create type support_status as enum ('received', 'extracted', 'confirmed', 'rejected', 'expired');
create type template_kind as enum ('activity_report', 'supervision_report', 'cover_letter', 'control_sheet');
create type template_status as enum ('draft', 'active', 'retired');
create type subscription_status as enum ('trial', 'active', 'past_due', 'suspended', 'canceled');
create type msg_direction as enum ('in', 'out');
create type ticket_status as enum ('open', 'in_progress', 'closed');
create type data_request_kind as enum ('access', 'rectification', 'deletion');

-- ---------------------------------------------------------------------------
-- Staff (panel users) and helper functions for RLS
-- ---------------------------------------------------------------------------
create table staff_members (
  auth_user_id uuid primary key references auth.users(id) on delete cascade,
  role         staff_role not null,
  full_name    text not null,
  created_at   timestamptz not null default now()
);

create or replace function is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from staff_members where auth_user_id = auth.uid());
$$;

create or replace function is_superadmin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from staff_members where auth_user_id = auth.uid() and role = 'superadmin');
$$;

-- ---------------------------------------------------------------------------
-- Organizations (future corporate client) and entities
-- ---------------------------------------------------------------------------
create table organizations (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  nit          text,
  billing_plan jsonb not null default '{}'::jsonb,
  created_at   timestamptz not null default now()
);

create table entities (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid references organizations(id),
  name            text not null,
  short_name      text not null,                 -- e.g. 'HRNO'
  nit             text,
  municipality    text,
  department      text,
  logo_path       text,                          -- storage: templates/{entity_id}/logo.png
  -- Validated by Zod (EntitySettings): default period kind/cutoff, proration
  -- convention, certificate validity days, IBC rules, PILA period rule,
  -- balance formulas, meeting hours, fixed legal texts, generate_with_missing.
  settings        jsonb not null default '{}'::jsonb,
  status          text not null default 'active' check (status in ('active', 'pending_templates', 'inactive')),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create table templates (
  id               uuid primary key default gen_random_uuid(),
  entity_id        uuid not null references entities(id),
  kind             template_kind not null,
  name             text not null,                -- e.g. 'Informe actividades – EBS'
  version          int not null,
  file_path        text not null,                -- storage: templates/...
  tags_used        text[] not null default '{}',
  status           template_status not null default 'draft',
  created_by       uuid references auth.users(id),
  created_at       timestamptz not null default now(),
  unique (entity_id, kind, name, version)
);

create table support_types (
  id              uuid primary key default gen_random_uuid(),
  entity_id       uuid not null references entities(id),
  code            text not null,                 -- PILA, POLICIA, RNMC, PROCURADURIA, ...
  label           text not null,
  required        boolean not null default true,
  frequency       support_frequency not null default 'every_period',
  max_age_days    int,                           -- validity window
  bundle          text,                          -- 'ANTECEDENTES', 'AFILIACIONES' or null (loose)
  bundle_order    int,
  unique (entity_id, code)
);

create table reminder_rules (
  id              uuid primary key default gen_random_uuid(),
  entity_id       uuid not null references entities(id),
  contract_id     uuid,                          -- optional override (fk added below)
  trigger_kind    text not null check (trigger_kind in ('day_of_month', 'days_before_period_end', 'period_end', 'days_before_contract_end')),
  trigger_value   int not null default 0,
  support_code    text,                          -- or null for an action reminder
  action          text,                          -- 'pay_pila', 'download_background_checks', 'close_report'
  wa_template     text not null,                 -- approved Meta template name
  send_at_local   time not null default '08:00',
  active          boolean not null default true
);

-- ---------------------------------------------------------------------------
-- Contractors (WhatsApp users)
-- ---------------------------------------------------------------------------
create table users (
  id                    uuid primary key default gen_random_uuid(),
  auth_user_id          uuid unique references auth.users(id),   -- future read-only portal
  phone_e164            text not null unique,
  full_name             text,
  doc_type              text check (doc_type in ('CC', 'CE', 'PPT', 'PA')),
  doc_number_enc        text,
  doc_number_bidx       text,
  doc_number_last4      text,
  doc_issued_in         text,
  tax_regime            text,
  bank_name             text,
  bank_account_type     text check (bank_account_type in ('ahorros', 'corriente', 'deposito_electronico')),
  bank_account_enc      text,
  bank_account_last4    text,
  signature_path_enc    text,                    -- encrypted storage path; only with consent
  signature_consent_at  timestamptz,
  status                user_status not null default 'onboarding',
  reminders_opt_out     boolean not null default false,
  daily_reminder_time   time,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  deleted_at            timestamptz
);
create index on users (doc_number_bidx);

create or replace function current_contractor_id() returns uuid
language sql stable security definer set search_path = public as $$
  select id from users where auth_user_id = auth.uid();
$$;

create table policy_versions (
  id           uuid primary key default gen_random_uuid(),
  kind         text not null check (kind in ('privacy_policy', 'terms')),
  version      text not null,
  url          text not null,
  published_at timestamptz not null default now(),
  unique (kind, version)
);

create table consents (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid references users(id),
  phone_e164        text not null,               -- kept even when consent is refused
  policy_version_id uuid not null references policy_versions(id),
  accepted          boolean not null,
  channel           text not null default 'whatsapp',
  evidence_wamid    text,
  created_at        timestamptz not null default now()
);

create table data_requests (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references users(id),
  kind         data_request_kind not null,
  status       text not null default 'open' check (status in ('open', 'done', 'rejected')),
  due_at       timestamptz not null,             -- 15 business days for deletion
  resolved_at  timestamptz,
  notes        text,
  created_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Contracts, obligations, periods
-- ---------------------------------------------------------------------------
create table contracts (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references users(id),
  entity_id          uuid not null references entities(id),
  number             text not null,              -- CPS-0330-2026
  secop_code         text,                       -- CO1.PCCNTR.9618889
  object_text        text not null,
  process_area       text,
  contract_profile   text,                       -- template variant, e.g. 'salud_publica', 'ebs'
  start_date         date not null,
  end_date           date not null,
  total_value        bigint not null check (total_value > 0),
  monthly_value      bigint not null check (monthly_value > 0),
  payments_count     int not null check (payments_count > 0),
  payment_label_fmt  text not null default 'NN DE NN',  -- or 'NN-NN'
  period_kind        period_kind not null default 'calendar',
  period_cutoff_day  int check (period_cutoff_day between 1 and 31),
  supervisor_name    text,
  supervisor_title   text,
  spending_officer   text,
  status             contract_status not null default 'draft',
  contract_pdf_path  text,
  clauses_pdf_path   text,
  extracted          jsonb,                      -- raw AI extraction + confidences
  confirmed_at       timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (entity_id, number),
  check (end_date >= start_date)
);
alter table reminder_rules add foreign key (contract_id) references contracts(id);

create table contract_amendments (
  id            uuid primary key default gen_random_uuid(),
  contract_id   uuid not null references contracts(id),
  kind          text not null check (kind in ('addition', 'extension', 'addition_extension', 'suspension')),
  signed_on     date not null,
  added_value   bigint not null default 0,
  new_end_date  date,
  notes         text
);

create table contract_templates (
  contract_id  uuid not null references contracts(id),
  kind         template_kind not null,
  template_id  uuid not null references templates(id),
  primary key (contract_id, kind)
);

create table obligations (
  id                 uuid primary key default gen_random_uuid(),
  contract_id        uuid not null references contracts(id) on delete cascade,
  kind               obligation_kind not null,
  number             int not null,
  literal_text       text not null,
  default_text       text not null default 'Actividad cumplida.',
  requires_evidence  boolean not null default false,
  unique (contract_id, kind, number)
);

create table periods (
  id                uuid primary key default gen_random_uuid(),
  contract_id       uuid not null references contracts(id),
  report_number     int not null,
  payment_number    int not null,
  date_from         date not null,
  date_to           date not null,
  amount            bigint not null,             -- prorated value to bill
  status            period_status not null default 'scheduled',
  closed_at         timestamptz,
  delivered_at      timestamptz,
  forced_with_missing boolean not null default false,  -- internal control only
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (contract_id, report_number),
  check (date_to >= date_from)
);
create index on periods (status, date_to);

-- ---------------------------------------------------------------------------
-- Social security, supports, notes, evidences, drafts, documents
-- ---------------------------------------------------------------------------
create table social_security_payments (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references users(id),
  operator           text,                       -- Aportes en Línea, SOI, Mi Planilla...
  sheet_number       text,
  auth_code          text,                       -- PIN / authorization number
  paid_on            date,
  contribution_month date,                       -- first day of the contribution month
  ibc                bigint,
  health_entity      text,  health_value  bigint,
  pension_entity     text,  pension_value bigint,
  fsp_value          bigint,
  arl_entity         text,  arl_value     bigint, arl_risk_class int,
  afc_value          bigint,
  total_value        bigint,
  bank               text,
  support_id         uuid,                       -- fk added below
  extracted          jsonb,
  confirmed_at       timestamptz,
  created_at         timestamptz not null default now()
);

create table period_social_security (
  period_id  uuid not null references periods(id) on delete cascade,
  ssp_id     uuid not null references social_security_payments(id) on delete cascade,
  primary key (period_id, ssp_id)
);

create table supports (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references users(id),
  period_id        uuid references periods(id),
  support_type_id  uuid references support_types(id),
  original_path    text not null,
  normalized_path  text,                         -- PDF
  mime_type        text,
  sha256           text not null,
  issued_on        date,
  valid_until      date,
  holder_name      text,
  holder_doc_bidx  text,
  coverage_from    date,                         -- ARL
  coverage_to      date,
  status           support_status not null default 'received',
  rejection_reason text,
  extracted        jsonb,
  created_at       timestamptz not null default now(),
  unique (user_id, sha256)                       -- same file sent twice
);
alter table social_security_payments add foreign key (support_id) references supports(id);

create table activity_notes (
  id                       uuid primary key default gen_random_uuid(),
  user_id                  uuid not null references users(id),
  contract_id              uuid references contracts(id),   -- null = unassigned
  activity_date            date not null,
  text                     text,
  transcript               text,
  audio_path               text,
  source_wamids            text[] not null default '{}',
  suggested_obligation_id  uuid references obligations(id),
  confirmed_obligation_id  uuid references obligations(id),
  confidence               numeric(4,3),
  created_at               timestamptz not null default now()
);
create index on activity_notes (contract_id, activity_date);

create table evidences (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references users(id),
  note_id        uuid references activity_notes(id),
  period_id      uuid references periods(id),
  obligation_id  uuid references obligations(id),
  file_path      text not null,
  caption        text,
  taken_on       date,
  sort_order     int not null default 0,
  included       boolean not null default true,
  created_at     timestamptz not null default now()
);

create table drafts (
  id              uuid primary key default gen_random_uuid(),
  period_id       uuid not null references periods(id) on delete cascade,
  obligation_id   uuid not null references obligations(id),
  version         int not null default 1,
  ai_text         text,
  user_text       text,
  final_text      text,
  status          text not null default 'pending' check (status in ('pending', 'needs_input', 'proposed', 'approved', 'not_applicable')),
  source_note_ids uuid[] not null default '{}',
  approved_at     timestamptz,
  unique (period_id, obligation_id, version)
);

create table generated_documents (
  id            uuid primary key default gen_random_uuid(),
  period_id     uuid not null references periods(id),
  kind          text not null,                   -- activity_report, supervision_report, antecedentes, afiliaciones, pila, zip
  version       int not null,
  template_id   uuid references templates(id),
  docx_path     text,
  pdf_path      text,
  sha256        text not null,
  size_bytes    bigint,
  generated_by  text not null,                   -- 'worker' | staff auth uid
  created_at    timestamptz not null default now(),
  unique (period_id, kind, version)
);

-- ---------------------------------------------------------------------------
-- Billing (Phase 3; created now to keep the model stable)
-- ---------------------------------------------------------------------------
create table plans (
  id                     uuid primary key default gen_random_uuid(),
  name                   text not null,
  monthly_price          bigint not null,
  multi_contract_discount_pct numeric(5,2) not null default 0,
  trial_days             int not null default 0,
  trial_periods          int not null default 1,
  active                 boolean not null default true
);

create table subscriptions (
  id              uuid primary key default gen_random_uuid(),
  contract_id     uuid not null references contracts(id),
  plan_id         uuid not null references plans(id),
  status          subscription_status not null default 'trial',
  paid_through    date,
  grace_until     date,
  created_at      timestamptz not null default now(),
  unique (contract_id)
);

create table payments (
  id                 uuid primary key default gen_random_uuid(),
  subscription_id    uuid not null references subscriptions(id),
  amount             bigint not null,
  currency           text not null default 'COP',
  wompi_reference    text unique,
  wompi_transaction  text unique,
  status             text not null,              -- PENDING, APPROVED, DECLINED, VOIDED, ERROR, REFUNDED_MANUAL
  covers_month       date,
  raw                jsonb,
  created_at         timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Messaging, conversation state, idempotency
-- ---------------------------------------------------------------------------
create table wa_inbound (
  wamid        text primary key,                 -- Meta message id: idempotency key
  phone_e164   text not null,
  received_at  timestamptz not null default now(),
  payload      jsonb not null,
  processed_at timestamptz
);

create table conversations (
  user_id          uuid primary key references users(id),
  flow             text not null default 'idle',
  step             text not null default 'start',
  context          jsonb not null default '{}'::jsonb,
  last_inbound_at  timestamptz,                  -- 24 h service window
  expires_at       timestamptz,
  updated_at       timestamptz not null default now()
);

create table messages (
  id          bigint generated always as identity primary key,
  user_id     uuid references users(id),
  direction   msg_direction not null,
  wamid       text,
  msg_type    text not null,                     -- text, audio, image, document, interactive, template
  summary     text,                              -- short, no sensitive data
  status      text,                              -- sent, delivered, read, failed
  created_at  timestamptz not null default now()
);
create index on messages (user_id, created_at desc);

create table outbound_messages (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references users(id),
  idempotency_key  text not null unique,
  kind             text not null check (kind in ('free', 'template')),
  payload          jsonb not null,
  status           text not null default 'queued' check (status in ('queued', 'sent', 'delivered', 'read', 'failed', 'dropped')),
  wamid            text unique,
  attempts         int not null default 0,
  last_error       text,
  pricing_category text,
  created_at       timestamptz not null default now(),
  sent_at          timestamptz
);

create table webhook_events (
  provider     text not null,                    -- 'meta_status', 'wompi'
  external_id  text not null,
  payload      jsonb not null,
  received_at  timestamptz not null default now(),
  primary key (provider, external_id)
);

create table support_tickets (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references users(id),
  subject     text not null,
  status      ticket_status not null default 'open',
  assigned_to uuid references auth.users(id),
  created_at  timestamptz not null default now(),
  closed_at   timestamptz
);

-- ---------------------------------------------------------------------------
-- Observability
-- ---------------------------------------------------------------------------
create table ai_usage (
  id                 bigint generated always as identity primary key,
  user_id            uuid references users(id),
  period_id          uuid references periods(id),
  purpose            text not null,              -- classify_note, extract_pila, draft_obligations...
  prompt_version     text not null,
  model              text not null,
  input_tokens       int not null,
  cache_read_tokens  int not null default 0,
  cache_write_tokens int not null default 0,
  output_tokens      int not null,
  cost_usd_micros    bigint not null,
  created_at         timestamptz not null default now()
);

create table events (                            -- append-only audit log
  id          bigint generated always as identity primary key,
  actor       text not null,                     -- 'user:<id>', 'staff:<uid>', 'system'
  action      text not null,
  subject     text,                              -- 'period:<id>'
  data        jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);
revoke update, delete on events from authenticated, anon;

create table job_failures (                      -- dead letter, visible in panel
  id          bigint generated always as identity primary key,
  queue       text not null,
  msg_id      bigint,
  payload     jsonb not null,
  error       text not null,
  attempts    int not null,
  retried_at  timestamptz,
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Queues
-- ---------------------------------------------------------------------------
select pgmq.create('inbound');
select pgmq.create('jobs');
select pgmq.create('outbound');

-- ---------------------------------------------------------------------------
-- RLS (pattern; every table gets RLS enabled + explicit policies)
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'staff_members','organizations','entities','templates','support_types','reminder_rules',
    'users','policy_versions','consents','data_requests','contracts','contract_amendments',
    'contract_templates','obligations','periods','social_security_payments','period_social_security',
    'supports','activity_notes','evidences','drafts','generated_documents','plans','subscriptions',
    'payments','wa_inbound','conversations','messages','outbound_messages','webhook_events',
    'support_tickets','ai_usage','events','job_failures'
  ] loop
    execute format('alter table %I enable row level security', t);
  end loop;
end $$;

-- Staff read access on operational tables (operators included).
create policy staff_read on contracts for select to authenticated using (is_staff());
create policy staff_read on periods   for select to authenticated using (is_staff());
create policy staff_read on users     for select to authenticated using (is_staff());
-- ... same pattern for the rest of the operational tables.

-- Superadmin-only tables: billing and configuration writes.
create policy superadmin_all on payments      for all to authenticated using (is_superadmin()) with check (is_superadmin());
create policy superadmin_all on subscriptions for all to authenticated using (is_superadmin()) with check (is_superadmin());
create policy superadmin_all on plans         for all to authenticated using (is_superadmin()) with check (is_superadmin());
create policy superadmin_write on entities    for all to authenticated using (is_superadmin()) with check (is_superadmin());
create policy superadmin_write on templates   for all to authenticated using (is_superadmin()) with check (is_superadmin());

-- Contractor (future read-only portal): own rows only.
create policy own_read on contracts for select to authenticated using (user_id = current_contractor_id());
create policy own_read on periods for select to authenticated
  using (exists (select 1 from contracts c where c.id = periods.contract_id and c.user_id = current_contractor_id()));
create policy own_read on generated_documents for select to authenticated
  using (exists (select 1 from periods p join contracts c on c.id = p.contract_id
                 where p.id = generated_documents.period_id and c.user_id = current_contractor_id()));

-- Operators never read raw inbound payloads, AI prompts or full billing data;
-- corrections go through security-definer RPCs that log to `events`.
-- Worker and Edge Functions use service_role (bypasses RLS) server-side only.
