-- Pechera: funciones que borran datos (un partido, una respuesta de convocatoria,
-- una fila de la planilla o un equipo guardado en la pizarra).
-- Se pegan en Supabase → SQL Editor → Run. Se pueden correr más de una vez.

create or replace function fc_match_delete(p_token uuid, p_match uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t uuid;
begin
  select team_id into t from fc_matches where id = p_match;
  perform _fc_staff(_uid(p_token), t);
  delete from fc_matches where id = p_match;
end $$;

create or replace function fc_rsvp(p_token uuid, p_match uuid, p_answer text, p_reason text default null, p_member uuid default null) returns void
language plpgsql security definer set search_path = public as $$
declare t uuid; me fc_members; target uuid;
begin
  select team_id into t from fc_matches where id = p_match;
  me := _fc_member(_uid(p_token), t);
  target := coalesce(p_member, me.id);
  if target <> me.id and me.role <> 'dt' then raise exception 'SOLO_DT'; end if;
  if not exists (select 1 from fc_members where id = target and team_id = t) then raise exception 'NO_PERMITIDO'; end if;
  if coalesce(p_answer,'') = '' then delete from fc_callups where match_id = p_match and member_id = target; return; end if;
  insert into fc_callups(match_id, member_id, answer, reason) values (p_match, target, p_answer, nullif(left(trim(coalesce(p_reason,'')), 120),''))
  on conflict (match_id, member_id) do update set answer = excluded.answer, reason = excluded.reason, updated_at = now();
end $$;

create or replace function fc_stats_save(p_token uuid, p_match uuid, p_member uuid, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare t uuid; me fc_members; staff boolean; mine boolean;
begin
  select team_id into t from fc_matches where id = p_match;
  me := _fc_member(_uid(p_token), t);
  staff := me.role = 'dt'; mine := p_member = me.id;
  if not mine and not staff then raise exception 'SOLO_DT'; end if;
  if not exists (select 1 from fc_members where id = p_member and team_id = t) then raise exception 'NO_PERMITIDO'; end if;
  if coalesce((p->>'remove')::boolean, false) then delete from fc_stats where match_id = p_match and member_id = p_member; return; end if;
  insert into fc_stats(match_id, member_id, by_self) values (p_match, p_member, mine and not staff) on conflict do nothing;
  update fc_stats set
    played = coalesce((p->>'played')::boolean, played),
    goals = coalesce((p->>'goals')::int, goals),
    assists = coalesce((p->>'assists')::int, assists),
    yellow = coalesce((p->>'yellow')::int, yellow),
    red = coalesce((p->>'red')::boolean, red),
    self_rating = case when mine and p ? 'self_rating' then nullif(p->>'self_rating','')::numeric else self_rating end,
    dt_rating = case when staff and p ? 'dt_rating' then nullif(p->>'dt_rating','')::numeric else dt_rating end,
    note = case when p ? 'note' then nullif(left(trim(p->>'note'), 200),'') else note end,
    by_self = case when staff and not mine then false else by_self end,
    updated_at = now()
  where match_id = p_match and member_id = p_member;
end $$;

create or replace function fc_lineup_delete(p_token uuid, p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t uuid;
begin
  select team_id into t from fc_lineups where id = p_id;
  perform _fc_staff(_uid(p_token), t);
  delete from fc_lineups where id = p_id;
end $$;
