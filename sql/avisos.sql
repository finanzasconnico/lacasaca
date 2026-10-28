-- La Casaca: notificaciones al celu. Se puede correr más de una vez.
-- Usa las mismas claves de Fueguitos (push_config) pero suscripciones propias, porque cada app tiene su service worker.
-- Las manda la función casaca-push (supabase/functions/casaca-push).

create table if not exists fc_push_subs (
  endpoint text primary key,
  user_id uuid not null,
  p256dh text not null,
  auth text not null,
  gone boolean not null default false,
  created_at timestamptz not null default now()
);
alter table fc_push_subs enable row level security;

-- Cuántos tiene que haber confirmados a 2 días del partido (por defecto: los de cancha + 3 suplentes)
alter table fc_teams add column if not exists min_players int;
alter table fc_matches add column if not exists alert_short_at timestamptz;
alter table fc_matches add column if not exists alert_boss_at timestamptz;
alter table fc_matches add column if not exists alert_players_at timestamptz;

create or replace function fc_push_subscribe(p_token uuid, p_endpoint text, p_p256dh text, p_auth text) returns void
language plpgsql security definer set search_path = public as $$
declare v uuid := _uid(p_token);
begin
  if p_endpoint !~ '^https://' or length(p_endpoint) > 1000 or coalesce(p_p256dh, '') = '' or coalesce(p_auth, '') = '' then raise exception 'DATOS_INVALIDOS'; end if;
  insert into fc_push_subs(endpoint, user_id, p256dh, auth) values (p_endpoint, v, p_p256dh, p_auth)
  on conflict (endpoint) do update set user_id = v, p256dh = excluded.p256dh, auth = excluded.auth, gone = false;
end $$;

create or replace function fc_push_unsubscribe(p_token uuid, p_endpoint text) returns void
language plpgsql security definer set search_path = public as $$
declare v uuid := _uid(p_token);
begin
  update fc_push_subs set gone = true where endpoint = p_endpoint and user_id = v;
end $$;

-- Para la función que manda: a quién (solo el servidor la puede usar)
create or replace function fc_push_rows(p_users uuid[]) returns table(endpoint text, p256dh text, auth text)
language sql security definer set search_path = public as $$
  select s.endpoint, s.p256dh, s.auth from fc_push_subs s where s.user_id = any(p_users) and not s.gone;
$$;
create or replace function fc_push_test_rows(p_token uuid) returns table(endpoint text, p256dh text, auth text)
language sql security definer set search_path = public as $$
  select s.endpoint, s.p256dh, s.auth from fc_push_subs s where s.user_id = _uid(p_token) and not s.gone;
$$;
create or replace function fc_push_gone(p_endpoint text) returns void
language sql security definer set search_path = public as $$ update fc_push_subs set gone = true where endpoint = p_endpoint; $$;

-- Manda un aviso a una lista de usuarios (lo hace la función casaca-push, en segundo plano)
create or replace function _fc_push(p_users uuid[], p_title text, p_body text, p_url text, p_tag text) returns void
language plpgsql security definer set search_path = public, net as $$
begin
  if p_users is null or cardinality(p_users) = 0 then return; end if;
  if not exists (select 1 from fc_push_subs where user_id = any(p_users) and not gone) then return; end if;
  perform net.http_post(
    url := 'https://ngwrtivemyjueiysqqum.supabase.co/functions/v1/casaca-push',
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'fueguitos_cron_secret')),
    body := jsonb_build_object('users', to_jsonb(p_users), 'title', p_title, 'body', p_body, 'url', p_url, 'tag', p_tag),
    timeout_milliseconds := 30000);
end $$;

-- Los del plantel que tienen cuenta (jugadores activos)
create or replace function _fc_team_users(p_team uuid, p_except uuid[] default '{}') returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(distinct m.user_id), '{}') from fc_members m
  where m.team_id = p_team and m.active and m.plays and not coalesce(m.guest, false) and m.user_id is not null
    and not (m.id = any(p_except));
$$;

-- Entrenamiento nuevo: le avisa a todo el plantel. Se junta por minuto, así un plan semanal llega como un solo aviso.
alter table fc_trainings add column if not exists announced_at timestamptz;
update fc_trainings set announced_at = coalesce(announced_at, created_at, now()) where announced_at is null;
create or replace function fc_push_trainings() returns int
language plpgsql security definer set search_path = public as $$
declare g record; t fc_trainings; who text; n int := 0;
begin
  for g in select team_id, created_by, array_agg(id order by coalesce(starts_at, due_at), created_at) ids, count(*) c
           from fc_trainings where announced_at is null and created_at < now() - interval '40 seconds'
           group by team_id, created_by loop
    update fc_trainings set announced_at = now() where id = any(g.ids);
    select * into t from fc_trainings where id = g.ids[1];
    select name into who from fc_members where team_id = g.team_id and (id = g.created_by or user_id = g.created_by) limit 1;
    perform _fc_push(
      _fc_team_users(g.team_id, array(select id from fc_members where team_id = g.team_id and (id = g.created_by or user_id = g.created_by))),
      case when g.c > 1 then '🗓️ ' || coalesce(who, 'El DT') || ' mandó el plan de la semana'
           when t.kind = 'cancha' then '📍 Entrenamiento: ' || t.title
           else '🏋️ ' || coalesce(who, 'El DT') || ' mandó un entrenamiento' end,
      case when g.c > 1 then g.c || ' entrenamientos: ' || (select string_agg(title, ', ' order by coalesce(starts_at, due_at)) from fc_trainings where id = any(g.ids)) || '.'
           when t.kind = 'cancha'
             then coalesce(to_char(t.starts_at at time zone 'America/Argentina/Buenos_Aires', 'DD/MM HH24:MI') || ' h', 'Fecha a confirmar') || coalesce(' · ' || t.venue, '') || '. ¿Vas?'
           else t.title || coalesce(' · hasta el ' || to_char(t.due_at at time zone 'America/Argentina/Buenos_Aires', 'DD/MM'), '') || case when t.proof then '. Mandá la foto cuando lo termines.' else '' end end,
      './?team=' || g.team_id || case when g.c > 1 then '&tab=entrenos' else '&t=' || t.id end, 'entreno-' || t.id);
    n := n + 1;
  end loop;
  return n;
end $$;

-- Alguien hizo el entrenamiento: les avisa a los que todavía no lo hicieron (el aviso se reemplaza, no se acumula)
create or replace function _fc_training_done_trg() returns trigger
language plpgsql security definer set search_path = public as $$
declare t fc_trainings; who text; done int; total int;
begin
  if new.status <> 'hecho' or (tg_op = 'UPDATE' and old.status = 'hecho') then return new; end if;
  select * into t from fc_trainings where id = new.training_id;
  if t.id is null or (t.due_at is not null and t.due_at < now()) then return new; end if;
  select name into who from fc_members where id = new.member_id;
  select count(*) into done from fc_training_logs where training_id = t.id and status = 'hecho';
  select count(*) into total from fc_members where team_id = t.team_id and active and plays and not coalesce(guest, false);
  perform _fc_push(
    _fc_team_users(t.team_id, array(select member_id from fc_training_logs where training_id = t.id and status in ('hecho', 'no_puedo'))),
    '💪 ' || coalesce(who, 'Uno del equipo') || ' ya hizo «' || t.title || '»',
    'Van ' || done || ' de ' || total || '. ¡Te falta a vos!',
    './?team=' || t.team_id || '&t=' || t.id, 'entreno-' || t.id);
  return new;
end $$;
create or replace trigger fc_training_done after insert or update of status on fc_training_logs for each row execute function _fc_training_done_trg();

-- Cada hora: faltan jugadores a 2 días del partido, y después del partido, cargar resultado y números.
create or replace function fc_push_matches() returns int
language plpgsql security definer set search_path = public as $$
declare x record; need int; yes int; n int := 0; hr int := extract(hour from now() at time zone 'America/Argentina/Buenos_Aires');
begin
  if hr < 9 or hr > 22 then return 0; end if;
  -- 1) A 2 días: si no llegan a los que hacen falta, avisa a los que no respondieron o dudan, y al DT.
  for x in select m.*, t.players_on_field, t.min_players from fc_matches m join fc_teams t on t.id = m.team_id
           where not m.played and m.alert_short_at is null and coalesce(t.kind, 'torneo') = 'torneo'
             and m.starts_at between now() + interval '12 hours' and now() + interval '48 hours' loop
    update fc_matches set alert_short_at = now() where id = x.id;
    need := coalesce(x.min_players, x.players_on_field + 3);
    select count(*) into yes from fc_callups c join fc_members mm on mm.id = c.member_id where c.match_id = x.id and c.answer = 'voy' and mm.active;
    if yes >= need then continue; end if;
    perform _fc_push(
      array(select distinct mm.user_id from fc_members mm left join fc_callups c on c.match_id = x.id and c.member_id = mm.id
            where mm.team_id = x.team_id and mm.active and mm.plays and not coalesce(mm.guest, false) and mm.user_id is not null
              and mm.role = 'jugador' and coalesce(mm.status, 'ok') = 'ok' and (c.answer is null or c.answer = 'duda')),
      '⚽ Faltan jugadores para vs ' || x.opponent,
      'Somos ' || yes || ' y necesitamos ' || need || '. ¿Vas? Confirmá en la app.',
      './?team=' || x.team_id || '&m=' || x.id, 'conv-' || x.id);
    perform _fc_push(
      array(select distinct mm.user_id from fc_members mm where mm.team_id = x.team_id and mm.active and mm.user_id is not null and (mm.role in ('dt', 'ayudante') or mm.id = x.dt_member)),
      '📋 vs ' || x.opponent || ': ' || yes || ' confirmados de ' || need,
      'Ya les avisamos a los que no respondieron. Mirá la convocatoria.',
      './?team=' || x.team_id || '&m=' || x.id, 'conv-dt-' || x.id);
    n := n + 1;
  end loop;
  -- 2) Dos horas después del partido sin resultado: al que lo dirige.
  for x in select m.* from fc_matches m where not m.played and m.alert_boss_at is null
           and m.starts_at between now() - interval '2 days' and now() - interval '2 hours' loop
    update fc_matches set alert_boss_at = now() where id = x.id;
    perform _fc_push(
      array(select distinct mm.user_id from fc_members mm where mm.team_id = x.team_id and mm.active and mm.user_id is not null
            and (mm.id = x.dt_member or (x.dt_member is null and mm.role in ('dt', 'ayudante')))),
      '🏁 ¿Cómo salió vs ' || x.opponent || '?', 'Cargá el resultado y los puntajes.',
      './?team=' || x.team_id || '&m=' || x.id, 'post-' || x.id);
    n := n + 1;
  end loop;
  -- 3) Con el resultado cargado: a los que jugaron (o confirmaron), que carguen sus números.
  for x in select m.* from fc_matches m where m.played and m.alert_players_at is null
           and coalesce(m.result_at, m.starts_at) > now() - interval '2 days' loop
    update fc_matches set alert_players_at = now() where id = x.id;
    perform _fc_push(
      array(select distinct mm.user_id from fc_members mm where mm.team_id = x.team_id and mm.active and mm.user_id is not null
            and (exists (select 1 from fc_callups c where c.match_id = x.id and c.member_id = mm.id and c.answer = 'voy')
                 or exists (select 1 from fc_stats s where s.match_id = x.id and s.member_id = mm.id and s.played))
            and not exists (select 1 from fc_stats s where s.match_id = x.id and s.member_id = mm.id and s.by_self)),
      '✍️ ' || coalesce(x.goals_for || '-' || x.goals_against || ' ', '') || 'vs ' || x.opponent || ': cargá tus números',
      'Goles, asistencias y tarjetas. Y votá la figura ⭐',
      './?team=' || x.team_id || '&m=' || x.id, 'post-' || x.id);
    n := n + 1;
  end loop;
  return n;
end $$;

-- Los partidos que ya pasaron no avisan nada al instalar esto
update fc_matches set alert_short_at = coalesce(alert_short_at, now()), alert_boss_at = coalesce(alert_boss_at, now()), alert_players_at = coalesce(alert_players_at, now())
where starts_at < now() - interval '1 day' or played;

-- fc_team devuelve el mínimo y Ajustes lo guarda
do $$ declare d text; begin
  d := pg_get_functiondef('fc_team'::regproc);
  if position('min_players' in d) = 0 then
    d := replace(d, '''ratings_public'', t.ratings_public,', '''ratings_public'', t.ratings_public, ''min_players'', t.min_players,');
    execute d;
  end if;
  d := pg_get_functiondef('fc_team_settings'::regproc);
  if position('min_players' in d) = 0 then
    d := replace(d, '    ratings_public = coalesce((p->>''ratings_public'')::boolean, ratings_public),',
      '    ratings_public = coalesce((p->>''ratings_public'')::boolean, ratings_public),
    min_players = case when p ? ''min_players'' then nullif(p->>''min_players'', '''')::int else min_players end,');
    execute d;
  end if;
end $$;

revoke all on function fc_push_rows(uuid[]), fc_push_test_rows(uuid), fc_push_gone(text), _fc_push(uuid[], text, text, text, text),
  _fc_team_users(uuid, uuid[]), fc_push_matches(), fc_push_trainings() from public, anon, authenticated;
grant execute on function fc_push_rows(uuid[]), fc_push_test_rows(uuid), fc_push_gone(text) to service_role;

select cron.schedule('casaca-avisos', '7 * * * *', 'select fc_push_matches()');
select cron.schedule('casaca-avisos-entrenos', '* * * * *', 'select fc_push_trainings() where exists (select 1 from fc_trainings where announced_at is null)');
