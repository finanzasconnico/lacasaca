-- La Casaca: pegar en Supabase (proyecto racha-app) → SQL Editor → Run.
-- Agrega ayudantes y DT por partido, y las funciones que confirman asistencia,
-- cargan números y borran partidos o equipos de la pizarra. Se puede correr más de una vez.

alter table fc_members drop constraint if exists fc_members_role_check;
alter table fc_members add constraint fc_members_role_check check (role in ('dt','ayudante','delegado','jugador'));
alter table fc_teams alter column ratings_public set default true;
alter table fc_matches add column if not exists dt_member uuid references fc_members(id) on delete set null;

-- DT o ayudante
create or replace function _fc_admin(p_uid uuid, p_team uuid) returns fc_members
language plpgsql stable security definer set search_path = public as $$
declare m fc_members := _fc_member(p_uid, p_team);
begin
  if m.role not in ('dt','ayudante') then raise exception 'SOLO_DT'; end if;
  return m;
end $$;

-- ¿Puede manejar este partido? DT, ayudante o el DT designado para ese partido.
create or replace function _fc_boss(p_me fc_members, p_match fc_matches) returns boolean
language sql stable set search_path = public as $$
  select p_me.role in ('dt','ayudante') or p_match.dt_member = p_me.id;
$$;

-- Pizarra: DT, ayudantes o quien tenga a cargo un partido que todavía no se jugó.
create or replace function _fc_board(p_uid uuid, p_team uuid) returns fc_members
language plpgsql stable security definer set search_path = public as $$
declare m fc_members := _fc_member(p_uid, p_team);
begin
  if m.role in ('dt','ayudante') or exists (select 1 from fc_matches where team_id = p_team and dt_member = m.id and not played) then return m; end if;
  raise exception 'SOLO_DT';
end $$;

revoke all on function _fc_admin(uuid, uuid), _fc_boss(fc_members, fc_matches), _fc_board(uuid, uuid) from public, anon, authenticated;

create or replace function fc_team(p_token uuid, p_team uuid) returns json
language plpgsql security definer set search_path = public as $$
declare v uuid := _uid(p_token); me fc_members := _fc_member(v, p_team); t fc_teams; staff boolean; pub boolean;
begin
  select * into t from fc_teams where id = p_team;
  staff := me.role = 'dt'; pub := staff or t.ratings_public;
  return json_build_object(
    'team', json_build_object('id', t.id, 'name', t.name, 'emoji', t.emoji, 'sport', t.sport, 'players_on_field', t.players_on_field,
      'category', t.category, 'ratings_public', t.ratings_public,
      'code', t.code, 'dt_code', case when staff then t.dt_code end),
    'me', json_build_object('id', me.id, 'role', me.role),
    'members', (select coalesce(json_agg(json_build_object('id', m.id, 'name', m.name, 'role', m.role, 'plays', m.plays, 'number', m.number,
        'positions', m.positions, 'foot', m.foot, 'status', m.status, 'status_until', m.status_until, 'status_note', m.status_note,
        'claimed', m.user_id is not null, 'active', m.active,
        'overall', case when pub or m.id = me.id then m.overall end,
        'attrs', case when pub or m.id = me.id then m.attrs else '{}'::jsonb end) order by m.name), '[]'::json)
      from fc_members m where m.team_id = p_team),
    'matches', (select coalesce(json_agg(json_build_object('id', x.id, 'opponent', x.opponent, 'starts_at', x.starts_at, 'venue', x.venue, 'kind', x.kind,
        'goals_for', x.goals_for, 'goals_against', x.goals_against, 'difficulty', x.difficulty, 'notes', x.notes, 'played', x.played,
        'result_at', x.result_at, 'sort', x.sort, 'dt_member', x.dt_member) order by coalesce(x.starts_at, x.created_at), x.sort), '[]'::json)
      from fc_matches x where x.team_id = p_team),
    'callups', (select coalesce(json_agg(json_build_object('match_id', c.match_id, 'member_id', c.member_id, 'answer', c.answer, 'reason', c.reason)), '[]'::json)
      from fc_callups c join fc_matches x on x.id = c.match_id where x.team_id = p_team),
    'stats', (select coalesce(json_agg(json_build_object('match_id', s.match_id, 'member_id', s.member_id, 'played', s.played, 'goals', s.goals,
        'assists', s.assists, 'yellow', s.yellow, 'red', s.red, 'by_self', s.by_self,
        'note', case when staff or s.member_id = me.id or x.dt_member = me.id then s.note end,
        'self_rating', case when staff or s.member_id = me.id or x.dt_member = me.id then s.self_rating end,
        'dt_rating', case when pub or s.member_id = me.id or x.dt_member = me.id then s.dt_rating end)), '[]'::json)
      from fc_stats s join fc_matches x on x.id = s.match_id where x.team_id = p_team),
    'votes', (select coalesce(json_agg(json_build_object('match_id', w.match_id, 'voted_id', w.voted_id, 'mine', w.voter_id = me.id)), '[]'::json)
      from fc_votes w join fc_matches x on x.id = w.match_id where x.team_id = p_team),
    'lineups', (select coalesce(json_agg(json_build_object('id', l.id, 'match_id', l.match_id, 'name', l.name, 'formation', l.formation,
        'slots', l.slots, 'notes', l.notes, 'updated_at', l.updated_at) order by l.updated_at desc), '[]'::json)
      from fc_lineups l where l.team_id = p_team)
  );
end $$;

-- Fichas: DT y ayudantes agregan y editan; puntaje, atributos y roles, solo el DT.
create or replace function fc_member_save(p_token uuid, p_team uuid, p_id uuid, p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare me fc_members := _fc_member(_uid(p_token), p_team); staff boolean := me.role = 'dt'; adm boolean := me.role in ('dt','ayudante'); m uuid := p_id;
begin
  if m is null then
    if not adm then raise exception 'SOLO_DT'; end if;
    if coalesce(trim(p->>'name'),'') = '' then raise exception 'DATOS_INVALIDOS'; end if;
    insert into fc_members(team_id, name) values (p_team, left(trim(p->>'name'), 30)) returning id into m;
  elsif not exists (select 1 from fc_members where id = m and team_id = p_team) then raise exception 'NO_PERMITIDO';
  elsif m <> me.id and not adm then raise exception 'SOLO_DT';
  end if;
  update fc_members set
    name = coalesce(nullif(left(trim(p->>'name'), 30), ''), name),
    number = case when p ? 'number' then nullif(p->>'number','')::int else number end,
    positions = case when p ? 'positions' then array(select jsonb_array_elements_text(p->'positions')) else positions end,
    foot = case when p ? 'foot' then nullif(p->>'foot','') else foot end,
    status = coalesce(nullif(p->>'status',''), status),
    status_until = case when p ? 'status_until' then nullif(p->>'status_until','')::date else status_until end,
    status_note = case when p ? 'status_note' then nullif(left(trim(p->>'status_note'), 120),'') else status_note end,
    overall = case when staff and p ? 'overall' then nullif(p->>'overall','')::int else overall end,
    attrs = case when staff and p ? 'attrs' then p->'attrs' else attrs end,
    plays = case when staff and p ? 'plays' then (p->>'plays')::boolean else plays end,
    role = case when staff and p ? 'role' and id <> me.id then p->>'role' else role end,
    active = case when adm and p ? 'active' and id <> me.id and (staff or role <> 'dt') then (p->>'active')::boolean else active end
  where id = m;
  return m;
end $$;

-- Partidos: crean DT y ayudantes; el DT del partido también edita el suyo y carga el resultado.
create or replace function fc_match_save(p_token uuid, p_team uuid, p_id uuid, p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare me fc_members := _fc_member(_uid(p_token), p_team); adm boolean := me.role in ('dt','ayudante'); x uuid := p_id; was boolean; mx fc_matches;
begin
  if x is null then
    if not adm then raise exception 'SOLO_DT'; end if;
    insert into fc_matches(team_id, opponent) values (p_team, left(trim(coalesce(nullif(p->>'opponent',''),'Rival')), 40)) returning id into x;
  else
    select * into mx from fc_matches where id = x and team_id = p_team;
    if mx.id is null then raise exception 'NO_PERMITIDO'; end if;
    if not _fc_boss(me, mx) then raise exception 'SOLO_DT'; end if;
  end if;
  select played into was from fc_matches where id = x;
  update fc_matches set
    opponent = coalesce(nullif(left(trim(p->>'opponent'), 40), ''), opponent),
    starts_at = case when p ? 'starts_at' then nullif(p->>'starts_at','')::timestamptz else starts_at end,
    venue = case when p ? 'venue' then nullif(left(trim(p->>'venue'), 60),'') else venue end,
    kind = coalesce(nullif(p->>'kind',''), kind),
    goals_for = case when p ? 'goals_for' then nullif(p->>'goals_for','')::int else goals_for end,
    goals_against = case when p ? 'goals_against' then nullif(p->>'goals_against','')::int else goals_against end,
    difficulty = case when p ? 'difficulty' then nullif(p->>'difficulty','')::int else difficulty end,
    notes = case when p ? 'notes' then nullif(left(trim(p->>'notes'), 500),'') else notes end,
    played = coalesce((p->>'played')::boolean, played),
    result_at = case when coalesce((p->>'played')::boolean, played) and not was then now() else result_at end,
    dt_member = case when adm and p ? 'dt_member' and (nullif(p->>'dt_member','') is null or exists (select 1 from fc_members where id = (p->>'dt_member')::uuid and team_id = p_team))
                     then nullif(p->>'dt_member','')::uuid else dt_member end
  where id = x;
  return x;
end $$;

create or replace function fc_match_delete(p_token uuid, p_match uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t uuid;
begin
  select team_id into t from fc_matches where id = p_match;
  perform _fc_admin(_uid(p_token), t);
  delete from fc_matches where id = p_match;
end $$;

create or replace function fc_rsvp(p_token uuid, p_match uuid, p_answer text, p_reason text default null, p_member uuid default null) returns void
language plpgsql security definer set search_path = public as $$
declare x fc_matches; me fc_members; target uuid;
begin
  select * into x from fc_matches where id = p_match;
  me := _fc_member(_uid(p_token), x.team_id);
  target := coalesce(p_member, me.id);
  if target <> me.id and not _fc_boss(me, x) then raise exception 'SOLO_DT'; end if;
  if not exists (select 1 from fc_members where id = target and team_id = x.team_id) then raise exception 'NO_PERMITIDO'; end if;
  if coalesce(p_answer,'') = '' then delete from fc_callups where match_id = p_match and member_id = target; return; end if;
  insert into fc_callups(match_id, member_id, answer, reason) values (p_match, target, p_answer, nullif(left(trim(coalesce(p_reason,'')), 120),''))
  on conflict (match_id, member_id) do update set answer = excluded.answer, reason = excluded.reason, updated_at = now();
end $$;

-- Números: cada uno los suyos; DT, ayudantes y el DT del partido, los de todos. Puntaje: DT o DT del partido.
create or replace function fc_stats_save(p_token uuid, p_match uuid, p_member uuid, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare x fc_matches; me fc_members; boss boolean; rater boolean; mine boolean;
begin
  select * into x from fc_matches where id = p_match;
  me := _fc_member(_uid(p_token), x.team_id);
  boss := _fc_boss(me, x); rater := me.role = 'dt' or x.dt_member = me.id; mine := p_member = me.id;
  if not mine and not boss then raise exception 'SOLO_DT'; end if;
  if not exists (select 1 from fc_members where id = p_member and team_id = x.team_id) then raise exception 'NO_PERMITIDO'; end if;
  if coalesce((p->>'remove')::boolean, false) then delete from fc_stats where match_id = p_match and member_id = p_member; return; end if;
  insert into fc_stats(match_id, member_id, by_self) values (p_match, p_member, mine and not boss) on conflict do nothing;
  update fc_stats set
    played = coalesce((p->>'played')::boolean, played),
    goals = coalesce((p->>'goals')::int, goals),
    assists = coalesce((p->>'assists')::int, assists),
    yellow = coalesce((p->>'yellow')::int, yellow),
    red = coalesce((p->>'red')::boolean, red),
    self_rating = case when mine and p ? 'self_rating' then nullif(p->>'self_rating','')::numeric else self_rating end,
    dt_rating = case when rater and p ? 'dt_rating' then nullif(p->>'dt_rating','')::numeric else dt_rating end,
    note = case when p ? 'note' then nullif(left(trim(p->>'note'), 200),'') else note end,
    by_self = case when boss and not mine then false else by_self end,
    updated_at = now()
  where match_id = p_match and member_id = p_member;
end $$;

create or replace function fc_lineup_save(p_token uuid, p_team uuid, p_id uuid, p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare me fc_members := _fc_board(_uid(p_token), p_team); l uuid := p_id;
begin
  if l is null then
    insert into fc_lineups(team_id, formation) values (p_team, coalesce(p->>'formation','')) returning id into l;
  elsif not exists (select 1 from fc_lineups where id = l and team_id = p_team) then raise exception 'NO_PERMITIDO';
  end if;
  update fc_lineups set
    name = coalesce(nullif(left(trim(p->>'name'), 40),''), name),
    formation = coalesce(nullif(p->>'formation',''), formation),
    slots = coalesce(p->'slots', slots),
    notes = coalesce(p->'notes', notes),
    match_id = case when p ? 'match_id' then nullif(p->>'match_id','')::uuid else match_id end,
    updated_at = now()
  where id = l;
  return l;
end $$;

create or replace function fc_lineup_delete(p_token uuid, p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t uuid;
begin
  select team_id into t from fc_lineups where id = p_id;
  perform _fc_board(_uid(p_token), t);
  delete from fc_lineups where id = p_id;
end $$;

-- Entrenamientos: borrar uno (DT y ayudantes). El resto del módulo ya está en la base.
create or replace function fc_training_delete(p_token uuid, p_training uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t uuid;
begin
  select team_id into t from fc_trainings where id = p_training;
  perform _fc_admin(_uid(p_token), t);
  delete from fc_trainings where id = p_training;
end $$;
