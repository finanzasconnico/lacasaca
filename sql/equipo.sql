-- La Casaca: fc_team y fc_member_save completas y al día. Se puede correr más de una vez.
-- (Reemplaza las versiones de sql/viejo/actualizar.sql, que no hay que volver a correr.)

alter table fc_members add column if not exists career jsonb;

create or replace function fc_team(p_token uuid, p_team uuid) returns json
language plpgsql security definer set search_path = public as $$
declare v uuid := _uid(p_token); me fc_members := _fc_member(v, p_team); t fc_teams; staff boolean; pub boolean; adm boolean;
begin
  select * into t from fc_teams where id = p_team;
  staff := me.role = 'dt'; adm := me.role in ('dt', 'ayudante'); pub := staff or t.ratings_public;
  return json_build_object(
    'team', json_build_object('id', t.id, 'name', t.name, 'emoji', t.emoji, 'sport', t.sport, 'players_on_field', t.players_on_field,
      'category', t.category, 'ratings_public', t.ratings_public, 'board_suggest', t.board_suggest, 'min_players', t.min_players,
      'kind', t.kind, 'place', t.place, 'place_url', t.place_url, 'usual_day', t.usual_day, 'usual_time', t.usual_time, 'usual_size', t.usual_size,
      'price', t.price, 'alias', t.alias, 'pinned', t.pinned, 'card_mode', t.card_mode,
      'league', exists (select 1 from fc_leagues lg where lg.team_id = t.id),
      'code', t.code, 'dt_code', case when staff then t.dt_code end),
    'me', json_build_object('id', me.id, 'role', me.role),
    'members', (select coalesce(json_agg(json_build_object('id', m.id, 'name', m.name, 'role', m.role, 'plays', m.plays, 'number', m.number,
        'positions', m.positions, 'foot', m.foot, 'status', m.status, 'status_until', m.status_until, 'status_note', m.status_note,
        'claimed', m.user_id is not null, 'active', m.active, 'guest', m.guest, 'ext_player_id', m.ext_player_id, 'career', m.career,
        'contact', case when adm then m.contact end,
        'overall', case when pub or m.id = me.id then m.overall end,
        'attrs', case when pub or m.id = me.id then m.attrs else '{}'::jsonb end) order by m.name), '[]'::json)
      from fc_members m where m.team_id = p_team),
    'matches', (select coalesce(json_agg(json_build_object('id', x.id, 'opponent', x.opponent, 'starts_at', x.starts_at, 'venue', x.venue, 'kind', x.kind,
        'goals_for', x.goals_for, 'goals_against', x.goals_against, 'difficulty', x.difficulty, 'notes', x.notes, 'played', x.played,
        'result_at', x.result_at, 'sort', x.sort, 'dt_member', x.dt_member, 'fecha_label', x.fecha_label, 'ext_id', x.ext_id)
        order by coalesce(x.starts_at, x.created_at), x.sort), '[]'::json)
      from fc_matches x where x.team_id = p_team),
    'callups', (select coalesce(json_agg(json_build_object('match_id', c.match_id, 'member_id', c.member_id, 'answer', c.answer, 'reason', c.reason)), '[]'::json)
      from fc_callups c join fc_matches x on x.id = c.match_id where x.team_id = p_team),
    'stats', (select coalesce(json_agg(json_build_object('match_id', s.match_id, 'member_id', s.member_id, 'played', s.played, 'goals', s.goals,
        'assists', s.assists, 'yellow', s.yellow, 'red', s.red, 'by_self', s.by_self, 'official', s.official,
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

create or replace function fc_member_save(p_token uuid, p_team uuid, p_id uuid, p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare me fc_members := _fc_member(_uid(p_token), p_team); v_card text := (select card_mode from fc_teams where id = p_team);
  staff boolean := me.role = 'dt'; adm boolean := me.role in ('dt','ayudante'); m uuid := p_id;
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
    overall = case when (staff or (v_card = 'staff' and adm) or (v_card = 'self' and id = me.id)) and p ? 'overall' then nullif(p->>'overall','')::int else overall end,
    attrs = case when (staff or (v_card = 'staff' and adm) or (v_card = 'self' and id = me.id)) and p ? 'attrs' then p->'attrs' else attrs end,
    plays = case when staff and p ? 'plays' then (p->>'plays')::boolean else plays end,
    role = case when staff and p ? 'role' and id <> me.id then p->>'role' else role end,
    guest = case when adm and p ? 'guest' then (p->>'guest')::boolean else guest end,
    contact = case when adm and p ? 'contact' then nullif(left(trim(p->>'contact'), 60), '') else contact end,
    ext_player_id = case when adm and p ? 'ext_player_id' then nullif(p->>'ext_player_id','')::int else ext_player_id end,
    career = case when (adm or id = me.id) and p ? 'career' and (jsonb_typeof(p->'career') in ('object', 'null')) and char_length((p->'career')::text) < 6000
                  then nullif(p->'career', 'null'::jsonb) else career end,
    active = case when adm and p ? 'active' and id <> me.id and (staff or role <> 'dt') then (p->>'active')::boolean else active end
  where id = m;
  return m;
end $$;
