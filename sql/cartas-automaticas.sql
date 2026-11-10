-- La Casaca: cartas automáticas. Se puede correr más de una vez.
-- La media, los cuatro atributos y las posiciones de cada jugador se recalculan solos con lo que pasa en la cancha:
-- puntajes del DT, goles, asistencias, cuánto juega, las figuras votadas y dónde lo pone el DT en la pizarra.
-- Si el DT ajusta una carta a mano, esa queda fija (card_locked) hasta que la vuelva a poner en automática.

alter table fc_teams add column if not exists auto_cards boolean not null default true;
alter table fc_members add column if not exists card_locked boolean not null default false;
alter table fc_members add column if not exists card_auto_at timestamptz;

create or replace function _fc_auto_cards(p_team uuid) returns int
language plpgsql security definer set search_path = public as $$
declare t fc_teams; r record; n int := 0; tot int; v numeric; ov int; pos text[]; z text; p0 text;
  off jsonb; a jsonb; k text; gk boolean; pj numeric; att numeric;
begin
  select * into t from fc_teams where id = p_team;
  if t.id is null or not t.auto_cards then return 0; end if;
  select count(*) into tot from fc_matches where team_id = p_team and played;
  for r in
    with pm as (select id, goals_against from fc_matches where team_id = p_team and played),
    st as (select s.member_id, count(*) pj, avg(s.dt_rating) filter (where s.dt_rating is not null) avg, count(s.dt_rating) rated,
             coalesce(sum(s.goals), 0) g, coalesce(sum(s.assists), 0) a, avg(pm.goals_against) gc
           from fc_stats s join pm on pm.id = s.match_id where s.played group by s.member_id),
    vt as (select w.match_id, w.voted_id, count(*) c from fc_votes w join fc_matches x on x.id = w.match_id
           where x.team_id = p_team and x.played and x.result_at < now() - interval '48 hours' group by 1, 2),
    fig as (select voted_id member_id, count(*) figs from vt where c = (select max(c) from vt v2 where v2.match_id = vt.match_id) group by 1),
    lu as (select (sl->>'m')::uuid member_id,
             case when coalesce((sl->>'gk')::boolean, false) then 'ARQ'
                  when (sl->>'y')::numeric > 58 then case when (sl->>'x')::numeric < 24 or (sl->>'x')::numeric > 76 then 'LAT' else 'DEF' end
                  when (sl->>'y')::numeric > 30 then case when (sl->>'x')::numeric < 20 or (sl->>'x')::numeric > 80 then 'EXT' else 'VOL' end
                  else case when (sl->>'x')::numeric < 24 or (sl->>'x')::numeric > 76 then 'EXT' else 'DEL' end end zone
           from fc_lineups l, jsonb_array_elements(l.slots) sl
           where l.team_id = p_team and coalesce(sl->>'m', '') ~ '^[0-9a-f-]{36}$'),
    lz as (select member_id, array_agg(zone order by c desc, zone) zones from (select member_id, zone, count(*) c from lu group by 1, 2) q group by 1)
    select m.id, m.positions, m.overall, m.attrs, st.pj, st.avg, st.rated, st.g, st.a, st.gc, coalesce(fig.figs, 0) figs, lz.zones
    from fc_members m left join st on st.member_id = m.id left join fig on fig.member_id = m.id left join lz on lz.member_id = m.id
    where m.team_id = p_team and m.active and m.plays and not m.card_locked
  loop
    -- Posiciones: primero donde lo pone el DT en la pizarra (de más a menos), después las que ya tenía
    pos := '{}';
    foreach z in array coalesce(r.zones, '{}') || coalesce(r.positions, '{}') loop
      if not (z = any(pos)) then pos := pos || z; end if;
    end loop;
    ov := r.overall; a := r.attrs;
    if coalesce(r.rated, 0) >= 2 then
      pj := greatest(r.pj, 1); att := case when tot > 0 then r.pj::numeric / tot else .6 end;
      -- La misma cuenta que la sugerencia de antes
      v := 40 + r.avg * 5 + least(6, r.g / pj * 6) + least(4, r.a / pj * 5) + greatest(-5, least(5, (att - .6) * 12)) + least(3, r.figs);
      ov := greatest(1, least(99, round(v)));
      p0 := coalesce(pos[1], '');
      gk := p0 = 'ARQ';
      off := case p0
        when 'ARQ' then '{"ata":4,"ref":3,"pie":-6,"ubi":1}'
        when 'DEF' then '{"vel":-2,"tec":-4,"fis":4,"def":8}'
        when 'LAT' then '{"vel":5,"tec":0,"fis":2,"def":3}'
        when 'VOL' then '{"vel":0,"tec":3,"fis":3,"def":2}'
        when 'ENG' then '{"vel":1,"tec":8,"fis":-3,"def":-6}'
        when 'EXT' then '{"vel":8,"tec":4,"fis":-1,"def":-9}'
        when 'DEL' then '{"vel":4,"tec":3,"fis":3,"def":-12}'
        else '{"vel":0,"tec":0,"fis":0,"def":0}' end::jsonb;
      a := '{}';
      for k in select jsonb_object_keys(off) loop
        v := ov + (off->>k)::int
          + case k when 'tec' then least(5, r.a / pj * 12) + least(3, r.g / pj * 4)
                   when 'vel' then least(3, r.g / pj * 4)
                   when 'fis' then greatest(-4, least(4, (att - .6) * 10))
                   when 'def' then greatest(-4, least(4, (1.5 - coalesce(r.gc, 1.5)) * 3))
                   when 'ata' then greatest(-4, least(4, (1.5 - coalesce(r.gc, 1.5)) * 4))
                   else 0 end;
        a := a || jsonb_build_object(k, greatest(40, least(99, round(v)))::int);
      end loop;
      ov := (select round(avg(value::int)) from jsonb_each_text(a));
    end if;
    if ov is distinct from r.overall or a is distinct from r.attrs or pos is distinct from r.positions then
      update fc_members set overall = ov, attrs = coalesce(a, '{}'), positions = pos, card_auto_at = now() where id = r.id;
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;
revoke all on function _fc_auto_cards(uuid) from public, anon, authenticated;

-- Se recalculan solas: cuando se cargan números o puntajes, cuando un partido pasa a jugado y cuando se guarda la pizarra
create or replace function _fc_auto_cards_trg() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_team uuid;
begin
  if tg_table_name = 'fc_stats' then select team_id into v_team from fc_matches where id = coalesce(new.match_id, old.match_id);
  else v_team := coalesce(new.team_id, old.team_id); end if;
  if v_team is not null then perform _fc_auto_cards(v_team); end if;
  return null;
end $$;
create or replace trigger fc_auto_cards_stats after insert or update of played, goals, assists, dt_rating on fc_stats for each row execute function _fc_auto_cards_trg();
create or replace trigger fc_auto_cards_match after update of played on fc_matches for each row execute function _fc_auto_cards_trg();
create or replace trigger fc_auto_cards_lineup after insert or update of slots on fc_lineups for each row execute function _fc_auto_cards_trg();

-- Una vez por día, para las figuras (se cuentan cuando cierra la votación, a las 48 h)
select cron.schedule('casaca-cartas', '20 9 * * *', 'select _fc_auto_cards(id) from fc_teams where auto_cards');

-- fc_team devuelve si la carta es automática; Ajustes prende o apaga; ajustar una carta a mano la deja fija
do $$ declare d text; begin
  d := pg_get_functiondef('fc_team'::regproc);
  if position('auto_cards' in d) = 0 then
    d := replace(d, '''card_mode'', t.card_mode,', '''card_mode'', t.card_mode, ''auto_cards'', t.auto_cards,');
    d := replace(d, '''career'', m.career,', '''career'', m.career, ''card_locked'', m.card_locked, ''card_auto_at'', m.card_auto_at,');
    execute d;
  end if;
  d := pg_get_functiondef('fc_team_settings'::regproc);
  if position('auto_cards' in d) = 0 then
    d := replace(d, '    ratings_public = coalesce((p->>''ratings_public'')::boolean, ratings_public),',
      '    ratings_public = coalesce((p->>''ratings_public'')::boolean, ratings_public),
    auto_cards = coalesce((p->>''auto_cards'')::boolean, auto_cards),');
    execute d;
  end if;
  d := pg_get_functiondef('fc_member_save'::regproc);
  if position('card_locked' in d) = 0 then
    d := replace(d, '    active = case when adm',
      '    card_locked = case when p ? ''card_locked'' and (staff or (v_card = ''staff'' and adm)) then (p->>''card_locked'')::boolean
                       when (p ? ''attrs'' or p ? ''overall'') and (staff or (v_card = ''staff'' and adm) or (v_card = ''self'' and id = me.id)) then true
                       else card_locked end,
    active = case when adm');
    execute d;
  end if;
end $$;

-- Ajustes al cambiar el modo: al prender las automáticas se recalculan todas
create or replace function _fc_auto_cards_team_trg() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.auto_cards and not coalesce(old.auto_cards, false) then perform _fc_auto_cards(new.id); end if;
  return null;
end $$;
create or replace trigger fc_auto_cards_team after update of auto_cards on fc_teams for each row execute function _fc_auto_cards_team_trg();

-- Volver una carta a automática (DT o ayudantes)
create or replace function fc_card_auto(p_token uuid, p_member uuid) returns void
language plpgsql security definer set search_path = public as $$
declare m fc_members; me fc_members;
begin
  select * into m from fc_members where id = p_member;
  if m.id is null then raise exception 'NO_EXISTE'; end if;
  me := _fc_admin(_uid(p_token), m.team_id);
  update fc_members set card_locked = false where id = p_member;
  perform _fc_auto_cards(m.team_id);
end $$;

-- Primera pasada para todos los equipos
select t.name, _fc_auto_cards(t.id) actualizadas from fc_teams t where t.auto_cards;
