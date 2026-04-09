create extension if not exists pgcrypto;

create table if not exists users (
  id uuid primary key default gen_random_uuid(),
  login text not null unique,
  password_hash text not null,
  created_at timestamptz not null default now()
);

create table if not exists groups (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  name text not null,
  "order" bigint not null default 0
);

create table if not exists tasks (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references groups(id) on delete cascade,
  title text not null,
  description text,
  is_completed boolean not null default false,
  priority text not null check (priority in ('low','medium','high')) default 'low',
  "order" bigint not null default 0,
  deadline timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz null
);

create table if not exists refresh_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  token_hash text not null,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  revoked_at timestamptz null
);

create table if not exists task_history (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null,
  action_type text not null check (action_type in ('create','update','delete','complete','reorder')),
  old_value jsonb,
  new_value jsonb,
  changed_at timestamptz not null default now(),
  changed_by uuid not null references users(id) on delete cascade
);

create index if not exists idx_groups_user_id on groups(user_id);
create index if not exists idx_tasks_group_id on tasks(group_id);
create index if not exists idx_tasks_updated_at on tasks(updated_at);
create index if not exists idx_task_history_task_id on task_history(task_id);
create index if not exists idx_refresh_tokens_user_id on refresh_tokens(user_id);
