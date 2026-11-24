-- Device Trail: server rules for sanitizing and admin renames.
-- Run once in Supabase: SQL Editor, New query, paste all of this, Run.
-- Safe to run again; it replaces the old versions.

-- 1. Admin role, so only an admin can rename a practice or rep everywhere at once.
alter table public.profiles add column if not exists role text not null default 'tech';

-- Make yourself admin. Put your sign-in email between the quotes, then run this line.
update public.profiles set role = 'admin'
where id = (select id from auth.users where email = 'PUT-YOUR-EMAIL-HERE');

-- 2. Sanitizing rule. A unit that comes back into the building from a practice, rep, or event
-- can sit at Check-in, but it can't move anywhere else until a Sanitized record is on its trail.
-- Returns before Nov 24, 2026 went through the old contamination closet and are left alone.
-- This matches the rule in the app, so a change that skips the app is stopped too.
create or replace function public.device_needs_sanitizing(d jsonb) returns boolean
language plpgsql immutable as $$
declare
  e jsonb;
  need boolean := false;
  field_locs text[] := array['customer','rep','event','sold'];
  out_locs text[] := array['event','customer','rep','sold','shipped'];
begin
  for e in select * from jsonb_array_elements(coalesce(d->'events','[]'::jsonb)) loop
    if e->>'t' = 'move'
       and e->'undone' is null
       and coalesce((e->>'isUndo')::boolean, false) = false
       and not ((e->>'to') = any(out_locs))
       and (((e->>'from') = any(field_locs))
            or (e->>'from' is null and coalesce((e->>'fromField')::boolean, false))) then
      need := (e->>'at') >= '2026-11-24T00:00:00.000Z';
    elsif need and (e->>'t' = 'sanitized' or (e->>'t' = 'dnr' and e->>'sanitized' = 'Yes')) then
      need := false;
    end if;
  end loop;
  return need;
end $$;

create or replace function public.enforce_sanitizing() returns trigger
language plpgsql as $$
begin
  if (tg_op = 'INSERT' or (new.doc->>'location') is distinct from (old.doc->>'location'))
     and coalesce(new.doc->>'location','') <> 'checkin'
     and public.device_needs_sanitizing(new.doc) then
    raise exception 'Device % is not sanitized. Record it sanitized before it moves on from Check-in.', new.doc->>'serial';
  end if;
  return new;
end $$;

drop trigger if exists devices_sanitizing on public.devices;
create trigger devices_sanitizing
  before insert or update on public.devices
  for each row execute function public.enforce_sanitizing();

-- 3. Check: run these two lines and look at the results. The first lists who can read and write
-- the devices table. The second lists every rule on it; you should see devices_sanitizing and
-- the history lock from stage 2.
select policyname, cmd, roles from pg_policies where tablename = 'devices';
select tgname from pg_trigger where tgrelid = 'public.devices'::regclass and not tgisinternal;
