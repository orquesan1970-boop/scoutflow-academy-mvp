-- ScoutFlow Academy MVP database draft
-- Supabase/PostgreSQL initial structure

create table academies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  country text,
  city text,
  primary_sport text,
  created_at timestamptz default now()
);

create table users_profile (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid references academies(id),
  full_name text not null,
  email text unique not null,
  role text not null,
  phone text,
  language text default 'es',
  created_at timestamptz default now()
);

create table players (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid references academies(id),
  scoutflow_id text unique,
  photo_url text,
  first_name text,
  last_name text,
  full_name text not null,
  birth_date date,
  birth_year int,
  gender text,
  nationality text[],
  residence_country text,
  city text,
  sport text,
  primary_position text,
  secondary_position text,
  height_cm int,
  weight_kg numeric,
  status text default 'Datos incompletos',
  scout_score int,
  responsible_user_id uuid references users_profile(id),
  created_at timestamptz default now()
);

create table player_access (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users_profile(id),
  player_id uuid references players(id),
  can_view_profile boolean default true,
  can_view_sport boolean default false,
  can_view_academic boolean default false,
  can_view_documents boolean default false,
  can_view_videos boolean default false,
  can_view_finance boolean default false,
  can_view_internal_notes boolean default false,
  can_edit boolean default false
);

create table documents (
  id uuid primary key default gen_random_uuid(),
  player_id uuid references players(id),
  document_type text not null,
  file_url text,
  status text default 'Pendiente',
  visible_to_family boolean default false,
  uploaded_by uuid references users_profile(id),
  created_at timestamptz default now()
);
