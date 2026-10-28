-- La Casaca: video fijado, quién arma las cartas, detalle del modo entrenar y borrar entrenamientos.
-- Se puede correr más de una vez.

alter table fc_teams add column if not exists pinned jsonb;
alter table fc_teams add column if not exists card_mode text not null default 'dt';
alter table fc_training_logs add column if not exists detail jsonb;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'fc_teams_card_mode_check') then
    alter table fc_teams add constraint fc_teams_card_mode_check check (card_mode in ('dt','staff','self'));
  end if;
end $$;

do $$ declare d text; begin
  -- fc_team devuelve el video fijado y quién arma las cartas
  d := pg_get_functiondef('fc_team'::regproc);
  if position('card_mode' in d) = 0 then
    d := replace(d, '''ratings_public'', t.ratings_public,', '''ratings_public'', t.ratings_public, ''pinned'', t.pinned, ''card_mode'', t.card_mode,');
    execute d;
  end if;
  -- Ajustes: quién arma las cartas
  d := pg_get_functiondef('fc_team_settings'::regproc);
  if position('card_mode' in d) = 0 then
    d := replace(d, '    ratings_public = coalesce((p->>''ratings_public'')::boolean, ratings_public),',
      '    ratings_public = coalesce((p->>''ratings_public'')::boolean, ratings_public),
    card_mode = case when p->>''card_mode'' in (''dt'',''staff'',''self'') then p->>''card_mode'' else card_mode end,');
    execute d;
  end if;
  -- Cartas: según el ajuste, también los ayudantes o cada jugador la suya
  d := pg_get_functiondef('fc_member_save'::regproc);
  if position('v_card' in d) = 0 then
    d := replace(d, 'declare me fc_members := _fc_member(_uid(p_token), p_team);',
      'declare me fc_members := _fc_member(_uid(p_token), p_team); v_card text := (select card_mode from fc_teams where id = p_team);');
    d := replace(d, '    overall = case when staff and p ? ''overall''',
      '    overall = case when (staff or (v_card = ''staff'' and adm) or (v_card = ''self'' and id = me.id)) and p ? ''overall''');
    d := replace(d, '    attrs = case when staff and p ? ''attrs''',
      '    attrs = case when (staff or (v_card = ''staff'' and adm) or (v_card = ''self'' and id = me.id)) and p ? ''attrs''');
    execute d;
  end if;
  -- Modo entrenar: guarda qué series hizo y con cuánto peso
  d := pg_get_functiondef('fc_training_log'::regproc);
  if position('detail' in d) = 0 then
    d := replace(d, '    source = coalesce(nullif(p->>''source'',''''), source),',
      '    source = coalesce(nullif(p->>''source'',''''), source),
    detail = case when p ? ''detail'' and char_length((p->''detail'')::text) < 8000 then p->''detail'' else detail end,');
    execute d;
  end if;
end $$;

-- Fijar un video de YouTube para todo el equipo (DT y ayudantes). Con p = null se saca.
create or replace function fc_team_pin(p_token uuid, p_team uuid, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare me fc_members := _fc_admin(_uid(p_token), p_team);
begin
  if p is null or jsonb_typeof(p) = 'null' then update fc_teams set pinned = null where id = p_team; return; end if;
  if coalesce(p->>'id','') !~ '^[A-Za-z0-9_-]{11}$' then raise exception 'DATOS_INVALIDOS'; end if;
  update fc_teams set pinned = jsonb_build_object('id', p->>'id', 'title', left(coalesce(p->>'title',''), 120), 'note', left(coalesce(p->>'note',''), 120), 'by', me.name, 'at', now())
  where id = p_team;
end $$;

-- Borrar un entrenamiento (DT y ayudantes)
create or replace function fc_training_delete(p_token uuid, p_training uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t uuid;
begin
  select team_id into t from fc_trainings where id = p_training;
  perform _fc_admin(_uid(p_token), t);
  delete from fc_trainings where id = p_training;
end $$;

-- Trae ya mismo goleadores, figuras, valla, fair play y suspendidos del torneo de Camarón.
update fc_leagues set last_request = null where torneo_id = 175;
select fc_league_fetch();
