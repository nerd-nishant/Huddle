-- ============================================================================
-- HUDDLE  -  Supabase schema, Row Level Security and attendance RPCs
-- Run once in Supabase > SQL Editor. Safe to re-run on an empty project.
-- ============================================================================

-- ---------- Institution structure -------------------------------------------
create table universities (id uuid primary key default gen_random_uuid(), name text not null unique);
create table colleges (
  id uuid primary key default gen_random_uuid(),
  university_id uuid not null references universities on delete cascade,
  name text not null);
create table departments (
  id uuid primary key default gen_random_uuid(),
  college_id uuid not null references colleges on delete cascade,
  name text not null);
create table subjects (
  id uuid primary key default gen_random_uuid(),
  department_id uuid not null references departments on delete cascade,
  semester int not null check (semester between 1 and 12),
  code text not null,
  name text not null);

-- ---------- People ----------------------------------------------------------
-- NOTE: profiles intentionally has NO phone / email column. Anything other
-- users can read about you is only username, name, avatar and academic info.
create table profiles (
  id uuid primary key references auth.users on delete cascade,
  role text not null check (role in ('student','teacher','institution')),
  username text not null unique check (username ~ '^[a-z0-9_.]{3,24}$'),
  full_name text not null default '' check (char_length(full_name) <= 80),
  avatar_url text,
  college_id uuid references colleges,
  department_id uuid references departments,
  semester int check (semester between 1 and 12),
  batch text check (char_length(batch) <= 20),
  is_authorised boolean not null default false,   -- teachers/institutions need approval
  created_at timestamptz not null default now());

-- Private contact data lives in its own table: only the owner can ever read it.
create table private_contacts (
  user_id uuid primary key references profiles on delete cascade,
  phone text);

create table enrollments (
  student_id uuid references profiles on delete cascade,
  subject_id uuid references subjects on delete cascade,
  primary key (student_id, subject_id));

create table teacher_assignments (
  teacher_id uuid references profiles on delete cascade,
  subject_id uuid references subjects on delete cascade,
  class_label text,                       -- e.g. "CSE Sem 5 - Batch A"
  primary key (teacher_id, subject_id));

-- ---------- Chat groups -----------------------------------------------------
create table fests (
  id uuid primary key default gen_random_uuid(),
  college_id uuid references colleges,
  university_id uuid references universities,
  name text not null,
  tagline text,
  description text,
  starts_on date, ends_on date,
  color text default '#8B5CF6');

create table groups (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in
    ('university','college','department','semester','batch','subject','fest_announce','fest_chat')),
  name text not null,
  description text,
  university_id uuid references universities,
  college_id uuid references colleges,
  department_id uuid references departments,
  semester int,
  batch text,
  subject_id uuid references subjects,
  fest_id uuid references fests on delete cascade,
  announcement_only boolean not null default false,
  is_private boolean not null default true,
  created_at timestamptz not null default now());

create table group_members (
  group_id uuid references groups on delete cascade,
  user_id uuid references profiles on delete cascade,
  role text not null default 'member' check (role in ('member','admin')),
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id));

create table messages (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references groups on delete cascade,
  sender_id uuid not null default auth.uid() references profiles on delete cascade,
  body text check (char_length(body) <= 4000),
  attachment_path text,
  attachment_name text,
  created_at timestamptz not null default now(),
  check (body is not null or attachment_path is not null));
create index on messages (group_id, created_at);

-- ---------- Updates ---------------------------------------------------------
create table updates (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('official','unofficial')),
  category text not null default 'Notice',
  title text not null check (char_length(title) between 3 and 140),
  body text not null check (char_length(body) between 3 and 5000),
  author_id uuid not null default auth.uid() references profiles on delete cascade,
  college_id uuid references colleges,
  created_at timestamptz not null default now());
create index on updates (kind, created_at desc);

-- ---------- Attendance ------------------------------------------------------
create table attendance_sessions (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references subjects,
  teacher_id uuid not null references profiles,
  title text not null,
  lat double precision not null,
  lng double precision not null,
  radius_m int not null check (radius_m between 20 and 500),
  qr_token text not null,          -- never readable by students (see RLS)
  prev_token text,
  token_updated_at timestamptz not null default now(),
  status text not null default 'open' check (status in ('open','closed')),
  created_at timestamptz not null default now(),
  closed_at timestamptz);

create table attendance_records (
  session_id uuid references attendance_sessions on delete cascade,
  student_id uuid references profiles on delete cascade,
  status text not null check (status in ('present','absent')),
  method text not null check (method in ('qr','manual','auto')),
  distance_m double precision,
  marked_at timestamptz not null default now(),
  primary key (session_id, student_id));
create index on attendance_records (student_id);

create table attendance_audit (
  id bigint generated always as identity primary key,
  session_id uuid not null,
  student_id uuid not null,
  old_status text,
  new_status text not null,
  method text,
  changed_by uuid,
  changed_at timestamptz not null default now());

-- ============================================================================
-- Helper functions
-- ============================================================================
create or replace function is_member(gid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from group_members where group_id = gid and user_id = auth.uid()) $$;

create or replace function is_group_admin(gid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from group_members where group_id = gid and user_id = auth.uid() and role = 'admin') $$;

create or replace function my_role() returns text
language sql stable security definer set search_path = public as $$
  select case when is_authorised then role end from profiles where id = auth.uid() $$;

create or replace function teaches(sid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from teacher_assignments ta join profiles p on p.id = ta.teacher_id
                 where ta.teacher_id = auth.uid() and ta.subject_id = sid
                   and p.role = 'teacher' and p.is_authorised) $$;

create or replace function username_available(u text) returns boolean
language sql stable security definer set search_path = public as $$
  select not exists (select 1 from profiles where username = lower(u)) $$;

-- ============================================================================
-- Triggers
-- ============================================================================
-- Create the profile when someone signs up. Only student/teacher can be chosen
-- from the app; institution accounts are created by an admin in the dashboard.
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare m jsonb := new.raw_user_meta_data; r text;
begin
  r := case when m->>'role' = 'teacher' then 'teacher' else 'student' end;
  insert into profiles (id, role, username, full_name, college_id, department_id, semester, batch, is_authorised)
  values (new.id, r, lower(m->>'username'), coalesce(left(m->>'full_name', 80), ''),
          nullif(m->>'college_id','')::uuid, nullif(m->>'department_id','')::uuid,
          nullif(m->>'semester','')::int, nullif(left(m->>'batch', 20),''),
          r = 'student');   -- teachers stay unauthorised until an admin approves
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

-- Users can edit their own profile but never promote themselves.
create or replace function protect_profile() returns trigger
language plpgsql as $$
begin
  if auth.uid() is not null and (new.role <> old.role or new.is_authorised <> old.is_authorised) then
    raise exception 'role and authorisation can only be changed by an administrator';
  end if;
  return new;
end $$;
create trigger protect_profile_cols before update on profiles
  for each row execute function protect_profile();

-- Every attendance change is logged.
create or replace function audit_attendance() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    insert into attendance_audit (session_id, student_id, old_status, new_status, method, changed_by)
    values (new.session_id, new.student_id,
            case when tg_op = 'UPDATE' then old.status end, new.status, new.method, auth.uid());
  end if;
  return new;
end $$;
create trigger attendance_audit_trg after insert or update on attendance_records
  for each row execute function audit_attendance();

-- ============================================================================
-- Attendance RPCs  (all checks happen on the server, not in the app)
-- ============================================================================
create or replace function start_session(
  p_subject uuid, p_title text, p_lat double precision, p_lng double precision, p_radius int)
returns uuid language plpgsql security definer set search_path = public as $$
declare v uuid;
begin
  if not teaches(p_subject) then raise exception 'You are not assigned to this subject'; end if;
  insert into attendance_sessions (subject_id, teacher_id, title, lat, lng, radius_m, qr_token)
  values (p_subject, auth.uid(), left(coalesce(nullif(trim(p_title), ''), 'Lecture'), 80),
          p_lat, p_lng, p_radius, replace(gen_random_uuid()::text, '-', ''))
  returning id into v;
  return v;
end $$;

-- Teacher's phone calls this every ~20s so a screenshot of the QR goes stale.
create or replace function rotate_session_token(p_session uuid) returns text
language plpgsql security definer set search_path = public as $$
declare t text := replace(gen_random_uuid()::text, '-', '');
begin
  update attendance_sessions
     set prev_token = qr_token, qr_token = t, token_updated_at = now()
   where id = p_session and teacher_id = auth.uid() and status = 'open';
  if not found then raise exception 'Session is closed or not yours'; end if;
  return t;
end $$;

create or replace function mark_attendance_qr(
  p_session uuid, p_token text, p_lat double precision, p_lng double precision)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s attendance_sessions; d double precision; a double precision; b double precision;
begin
  if my_role() is distinct from 'student' then raise exception 'Only students can mark attendance'; end if;
  select * into s from attendance_sessions where id = p_session;
  if not found or s.status <> 'open' then raise exception 'This lecture is not open for attendance'; end if;
  if not (p_token = s.qr_token or
          (p_token = s.prev_token and now() - s.token_updated_at < interval '30 seconds')) then
    raise exception 'QR code expired - scan the live code on the teacher''s screen';
  end if;
  if not exists (select 1 from enrollments where student_id = auth.uid() and subject_id = s.subject_id) then
    raise exception 'You are not enrolled in this subject';
  end if;
  -- haversine distance in metres
  a := sin(radians(p_lat - s.lat) / 2) ^ 2
     + cos(radians(s.lat)) * cos(radians(p_lat)) * sin(radians(p_lng - s.lng) / 2) ^ 2;
  d := 2 * 6371000 * asin(sqrt(a));
  if d > s.radius_m then
    raise exception 'You are % m away - move within % m of the classroom', round(d), s.radius_m;
  end if;
  insert into attendance_records (session_id, student_id, status, method, distance_m)
  values (p_session, auth.uid(), 'present', 'qr', d)
  on conflict (session_id, student_id)
  do update set status = 'present', method = 'qr', distance_m = d, marked_at = now();
  return jsonb_build_object('ok', true, 'distance_m', round(d));
end $$;

-- "Submit": closes the lecture and marks everyone without a record absent.
create or replace function close_session(p_session uuid) returns void
language plpgsql security definer set search_path = public as $$
declare s attendance_sessions;
begin
  select * into s from attendance_sessions where id = p_session and teacher_id = auth.uid();
  if not found or not teaches(s.subject_id) then raise exception 'Not your session'; end if;
  insert into attendance_records (session_id, student_id, status, method)
  select p_session, e.student_id, 'absent', 'auto' from enrollments e
   where e.subject_id = s.subject_id
  on conflict (session_id, student_id) do nothing;
  update attendance_sessions set status = 'closed', closed_at = now() where id = p_session;
end $$;

-- Student-facing summary. Scoped to the caller inside the view, so students
-- never need read access to sessions (which hold the QR token + location).
create or replace view attendance_summary as
select sub.id as subject_id, sub.name as subject_name, sub.code as subject_code,
       count(s.id)::int as total,
       (count(*) filter (where r.status = 'present'))::int as attended,
       (count(s.id) - count(*) filter (where r.status = 'present'))::int as missed
  from enrollments e
  join subjects sub on sub.id = e.subject_id
  left join attendance_sessions s on s.subject_id = e.subject_id and s.status = 'closed'
  left join attendance_records r on r.session_id = s.id and r.student_id = e.student_id
 where e.student_id = auth.uid()
 group by sub.id, sub.name, sub.code;

-- Dev convenience: put the caller into the groups / subjects that match their
-- profile. For a real rollout, replace with registrar imports.
create or replace function claim_my_groups() returns void
language plpgsql security definer set search_path = public as $$
declare p profiles; uni uuid;
begin
  select * into p from profiles where id = auth.uid();
  if not found or not p.is_authorised then return; end if;
  select university_id into uni from colleges where id = p.college_id;
  if p.role = 'student' then
    insert into enrollments (student_id, subject_id)
    select p.id, id from subjects where department_id = p.department_id and semester = p.semester
    on conflict do nothing;
  end if;
  insert into group_members (group_id, user_id)
  select g.id, p.id from groups g
   where g.fest_id is null
     and (g.university_id is null or g.university_id = uni)
     and (g.college_id is null or g.college_id = p.college_id)
     and (g.department_id is null or g.department_id = p.department_id)
     and (g.semester is null or g.semester = p.semester)
     and (g.batch is null or g.batch = p.batch)
     and (g.subject_id is null or exists (
            select 1 from enrollments e where e.student_id = p.id and e.subject_id = g.subject_id)
          or exists (select 1 from teacher_assignments t where t.teacher_id = p.id and t.subject_id = g.subject_id))
  on conflict do nothing;
end $$;

-- ============================================================================
-- Row Level Security
-- ============================================================================
alter table universities enable row level security;
alter table colleges enable row level security;
alter table departments enable row level security;
alter table subjects enable row level security;
alter table profiles enable row level security;
alter table private_contacts enable row level security;
alter table enrollments enable row level security;
alter table teacher_assignments enable row level security;
alter table fests enable row level security;
alter table groups enable row level security;
alter table group_members enable row level security;
alter table messages enable row level security;
alter table updates enable row level security;
alter table attendance_sessions enable row level security;
alter table attendance_records enable row level security;
alter table attendance_audit enable row level security;

-- Structure: readable by everyone (needed on the sign-up screen)
create policy "read" on universities for select using (true);
create policy "read" on colleges for select using (true);
create policy "read" on departments for select using (true);
create policy "read" on subjects for select to authenticated using (true);

-- Profiles: no phone/email inside, so reading is safe. Edit own only.
create policy "read" on profiles for select to authenticated using (true);
create policy "update own" on profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

create policy "own only" on private_contacts for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "own enrollments" on enrollments for select to authenticated
  using (student_id = auth.uid() or teaches(subject_id));
create policy "own assignments" on teacher_assignments for select to authenticated
  using (teacher_id = auth.uid());

create policy "read fests" on fests for select to authenticated using (true);

-- Groups: members see their groups; public fest groups are discoverable.
create policy "see groups" on groups for select to authenticated
  using (is_member(id) or (not is_private and fest_id is not null));

create policy "see co-members" on group_members for select to authenticated
  using (is_member(group_id));
create policy "join public fest" on group_members for insert to authenticated
  with check (user_id = auth.uid() and role = 'member' and exists (
    select 1 from groups g where g.id = group_id and g.fest_id is not null and not g.is_private));
create policy "leave" on group_members for delete to authenticated using (user_id = auth.uid());

create policy "read messages" on messages for select to authenticated using (is_member(group_id));
create policy "post messages" on messages for insert to authenticated
  with check (
    sender_id = auth.uid() and is_member(group_id) and
    (not (select announcement_only from groups where id = group_id) or is_group_admin(group_id)));
create policy "delete own message" on messages for delete to authenticated using (sender_id = auth.uid());

-- Updates: anyone signed in reads. Only authorised institution accounts publish OFFICIAL.
create policy "read updates" on updates for select to authenticated using (true);
create policy "publish official" on updates for insert to authenticated
  with check (kind = 'official' and author_id = auth.uid() and my_role() = 'institution');
create policy "post unofficial" on updates for insert to authenticated
  with check (kind = 'unofficial' and author_id = auth.uid() and my_role() in ('student','teacher'));
create policy "delete own update" on updates for delete to authenticated using (author_id = auth.uid());

-- Attendance. Students get SELECT on their own records and nothing else.
create policy "teacher sessions" on attendance_sessions for select to authenticated
  using (teacher_id = auth.uid() and teaches(subject_id));
create policy "own or taught records" on attendance_records for select to authenticated
  using (student_id = auth.uid() or exists (
    select 1 from attendance_sessions s where s.id = session_id and s.teacher_id = auth.uid()));
create policy "teacher marks" on attendance_records for insert to authenticated
  with check (exists (
    select 1 from attendance_sessions s
     where s.id = session_id and s.teacher_id = auth.uid() and teaches(s.subject_id)
       and exists (select 1 from enrollments e where e.student_id = attendance_records.student_id and e.subject_id = s.subject_id)));
create policy "teacher edits" on attendance_records for update to authenticated
  using (exists (select 1 from attendance_sessions s where s.id = session_id and s.teacher_id = auth.uid() and teaches(s.subject_id)))
  with check (method = 'manual');
create policy "audit visible" on attendance_audit for select to authenticated
  using (student_id = auth.uid() or exists (
    select 1 from attendance_sessions s where s.id = session_id and s.teacher_id = auth.uid()));
-- No insert/update/delete policy for students anywhere on attendance.

-- RPC permissions
revoke execute on all functions in schema public from public, anon;
grant execute on function username_available(text) to anon, authenticated;
grant execute on function start_session, rotate_session_token, mark_attendance_qr,
      close_session, claim_my_groups, is_member, is_group_admin, my_role, teaches to authenticated;

-- ============================================================================
-- Storage: avatars (public read) + study-docs (group members only)
-- ============================================================================
insert into storage.buckets (id, name, public) values ('avatars', 'avatars', true) on conflict do nothing;
insert into storage.buckets (id, name, public, file_size_limit)
  values ('study-docs', 'study-docs', false, 15728640) on conflict do nothing;

create policy "avatar read" on storage.objects for select using (bucket_id = 'avatars');
create policy "avatar write own" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "avatar update own" on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "docs read members" on storage.objects for select to authenticated
  using (bucket_id = 'study-docs' and is_member(((storage.foldername(name))[1])::uuid));
create policy "docs upload members" on storage.objects for insert to authenticated
  with check (bucket_id = 'study-docs' and is_member(((storage.foldername(name))[1])::uuid));

-- ============================================================================
-- Realtime
-- ============================================================================
alter publication supabase_realtime add table messages, attendance_records, updates;
