-- La Casaca: los goles y tarjetas de la planilla oficial pasan solos a las estadísticas de cada jugador vinculado.
-- (Ya cargado en la base.) Se vincula desde Tabla → Torneo → Vincular jugadores.

create or replace function _fc_league_sheet_stats(p_team uuid) returns int
language plpgsql security definer set search_path = public as $$
declare l fc_leagues; r record; n int := 0;
begin
  select * into l from fc_leagues where team_id = p_team;
  if l.team_id is null or l.team_ext_id is null then return 0; end if;
  for r in
    select x.id match_id, m.id member_id, p
    from fc_matches x
    join fc_league_matches lm on lm.team_id = x.team_id and lm.ext_id = x.ext_id and lm.sheet is not null and lm.status = 'FINA'
    cross join lateral jsonb_array_elements(case when lm.home_id = l.team_ext_id then lm.sheet->'h' else lm.sheet->'a' end) p
    join fc_members m on m.team_id = x.team_id and m.ext_player_id = (p->>'id')::int
    where x.team_id = p_team and x.ext_id is not null
  loop
    insert into fc_stats(match_id, member_id, played, official) values (r.match_id, r.member_id, true, true) on conflict do nothing;
    update fc_stats set played = true, official = true,
      goals = coalesce((r.p->>'g')::int, 0),
      yellow = least(coalesce((r.p->>'am')::int, 0), 2),
      red = coalesce((r.p->>'ro')::int, 0) > 0,
      updated_at = now()
    where match_id = r.match_id and member_id = r.member_id;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function _fc_league_sheet_stats(uuid) from public, anon, authenticated;

create or replace function _fc_member_link_trg() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.ext_player_id is not null and new.ext_player_id is distinct from old.ext_player_id then perform _fc_league_sheet_stats(new.team_id); end if;
  return new;
end $$;
create or replace trigger fc_member_link after update of ext_player_id on fc_members for each row execute function _fc_member_link_trg();

do $$ declare d text; begin
  d := pg_get_functiondef('fc_league_process'::regproc);
  if position('_fc_league_sheet_stats' in d) = 0 then
    d := replace(d, '      where team_id = q.team_id and ext_id = substr(q.kind, 7)::int;',
      '      where team_id = q.team_id and ext_id = substr(q.kind, 7)::int;
      perform _fc_league_sheet_stats(q.team_id);');
    execute d;
  end if;
end $$;
