-- La Casaca: equipos de amistosos (picadito). Se puede correr más de una vez.

-- Para qué es el equipo y los datos de siempre del picadito
alter table fc_teams add column if not exists kind text not null default 'torneo';
alter table fc_teams add column if not exists place text;
alter table fc_teams add column if not exists place_url text;
alter table fc_teams add column if not exists usual_day int;
alter table fc_teams add column if not exists usual_time text;
alter table fc_teams add column if not exists usual_size int;
alter table fc_teams add column if not exists price int;
alter table fc_teams add column if not exists alias text;

create table if not exists fc_pickups (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references fc_teams(id) on delete cascade,
  starts_at timestamptz,
  place text, place_url text,
  capacity int not null default 10 check (capacity between 2 and 40),
  price int, alias text, note text,
  status text not null default 'abierta' check (status in ('abierta','jugada','suspendida')),
  score_dark int, score_light int,
  organizer uuid references fc_members(id) on delete set null,
  finished_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists fc_pickups_team on fc_pickups(team_id, starts_at desc);
create table if not exists fc_pickup_players (
  pickup_id uuid not null references fc_pickups(id) on delete cascade,
  member_id uuid not null references fc_members(id) on delete cascade,
  status text not null check (status in ('va','no','lesionado')),
  side text check (side in ('oscuro','claro')),
  paid boolean not null default false,
  joined_at timestamptz not null default now(),
  primary key (pickup_id, member_id)
);
create table if not exists fc_pickup_goals (
  id uuid primary key default gen_random_uuid(),
  pickup_id uuid not null references fc_pickups(id) on delete cascade,
  member_id uuid references fc_members(id) on delete cascade,
  side text not null check (side in ('oscuro','claro')),
  undone boolean not null default false,
  created_by uuid references fc_members(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists fc_pickup_votes (
  pickup_id uuid not null references fc_pickups(id) on delete cascade,
  voter_id uuid not null references fc_members(id) on delete cascade,
  voted_id uuid not null references fc_members(id) on delete cascade,
  primary key (pickup_id, voter_id), check (voter_id <> voted_id)
);
alter table fc_pickups enable row level security;
alter table fc_pickup_players enable row level security;
alter table fc_pickup_goals enable row level security;
alter table fc_pickup_votes enable row level security;

do $$ declare d text; begin
  d := pg_get_functiondef('fc_team'::regproc);
  if position('usual_time' in d) = 0 then
    d := replace(d, '''ratings_public'', t.ratings_public,', '''ratings_public'', t.ratings_public, ''kind'', t.kind, ''place'', t.place, ''place_url'', t.place_url, ''usual_day'', t.usual_day, ''usual_time'', t.usual_time, ''usual_size'', t.usual_size, ''price'', t.price, ''alias'', t.alias,');
    execute d;
  end if;
  d := pg_get_functiondef('fc_team_settings'::regproc);
  if position('usual_time' in d) = 0 then
    d := replace(d, '    ratings_public = coalesce((p->>''ratings_public'')::boolean, ratings_public),',
      '    ratings_public = coalesce((p->>''ratings_public'')::boolean, ratings_public),
    kind = case when p->>''kind'' in (''torneo'',''amistosos'') then p->>''kind'' else kind end,
    place = case when p ? ''place'' then nullif(left(trim(p->>''place''), 80), '''') else place end,
    place_url = case when p ? ''place_url'' then nullif(left(trim(p->>''place_url''), 300), '''') else place_url end,
    usual_day = case when p ? ''usual_day'' then nullif(p->>''usual_day'', '''')::int else usual_day end,
    usual_time = case when p ? ''usual_time'' then nullif(left(p->>''usual_time'', 5), '''') else usual_time end,
    usual_size = case when p ? ''usual_size'' then nullif(p->>''usual_size'', '''')::int else usual_size end,
    price = case when p ? ''price'' then nullif(p->>''price'', '''')::int else price end,
    alias = case when p ? ''alias'' then nullif(left(trim(p->>''alias''), 60), '''') else alias end,');
    execute d;
  end if;
end $$;

-- Las fechas del picadito con todo lo de cada una
create or replace function fc_pickups(p_token uuid, p_team uuid) returns json
language plpgsql security definer set search_path = public as $$
declare me fc_members := _fc_member(_uid(p_token), p_team);
begin
  return (select coalesce(json_agg(json_build_object('id', k.id, 'starts_at', k.starts_at, 'place', k.place, 'place_url', k.place_url, 'capacity', k.capacity,
      'price', k.price, 'alias', k.alias, 'note', k.note, 'status', k.status, 'score_dark', k.score_dark, 'score_light', k.score_light,
      'organizer', k.organizer, 'finished_at', k.finished_at,
      'players', (select coalesce(json_agg(json_build_object('member_id', pp.member_id, 'status', pp.status, 'side', pp.side, 'paid', pp.paid, 'joined_at', pp.joined_at) order by pp.joined_at), '[]'::json) from fc_pickup_players pp where pp.pickup_id = k.id),
      'goals', (select coalesce(json_agg(json_build_object('id', g.id, 'member_id', g.member_id, 'side', g.side) order by g.created_at), '[]'::json) from fc_pickup_goals g where g.pickup_id = k.id and not g.undone),
      'votes', (select coalesce(json_agg(json_build_object('voted_id', v.voted_id, 'mine', v.voter_id = me.id)), '[]'::json) from fc_pickup_votes v where v.pickup_id = k.id)
    ) order by k.starts_at desc nulls first), '[]'::json)
    from (select * from fc_pickups where team_id = p_team order by starts_at desc nulls first limit 60) k);
end $$;

-- Abrir o editar una fecha: cualquiera del grupo (como pasa en WhatsApp)
create or replace function fc_pickup_save(p_token uuid, p_team uuid, p_id uuid, p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare me fc_members := _fc_member(_uid(p_token), p_team); t fc_teams; k uuid := p_id;
begin
  select * into t from fc_teams where id = p_team;
  if k is null then
    insert into fc_pickups(team_id, place, place_url, capacity, price, alias, organizer)
      values (p_team, t.place, t.place_url, coalesce(t.usual_size, 10), t.price, t.alias, me.id) returning id into k;
  elsif not exists (select 1 from fc_pickups where id = k and team_id = p_team) then raise exception 'NO_PERMITIDO';
  end if;
  update fc_pickups set
    starts_at = case when p ? 'starts_at' then nullif(p->>'starts_at','')::timestamptz else starts_at end,
    place = case when p ? 'place' then nullif(left(trim(p->>'place'), 80), '') else place end,
    place_url = case when p ? 'place_url' then nullif(left(trim(p->>'place_url'), 300), '') else place_url end,
    capacity = coalesce(nullif(p->>'capacity','')::int, capacity),
    price = case when p ? 'price' then nullif(p->>'price','')::int else price end,
    alias = case when p ? 'alias' then nullif(left(trim(p->>'alias'), 60), '') else alias end,
    note = case when p ? 'note' then nullif(left(trim(p->>'note'), 200), '') else note end,
    status = case when p->>'status' in ('abierta','suspendida') then p->>'status' else status end
  where id = k;
  return k;
end $$;

-- Me sumo / No puedo / Lesionado (cada uno, o alguien por otro)
create or replace function fc_pickup_join(p_token uuid, p_pickup uuid, p_member uuid, p_status text) returns void
language plpgsql security definer set search_path = public as $$
declare k fc_pickups; me fc_members; target uuid;
begin
  select * into k from fc_pickups where id = p_pickup;
  me := _fc_member(_uid(p_token), k.team_id);
  target := coalesce(p_member, me.id);
  if not exists (select 1 from fc_members where id = target and team_id = k.team_id) then raise exception 'NO_PERMITIDO'; end if;
  if p_status not in ('va','no','lesionado') then raise exception 'DATOS_INVALIDOS'; end if;
  insert into fc_pickup_players(pickup_id, member_id, status) values (p_pickup, target, p_status)
  on conflict (pickup_id, member_id) do update set status = excluded.status,
    joined_at = case when fc_pickup_players.status <> 'va' and excluded.status = 'va' then now() else fc_pickup_players.joined_at end,
    side = case when excluded.status = 'va' then fc_pickup_players.side end;
end $$;

-- Sumar a alguien que no está en la app (queda como invitado)
create or replace function fc_pickup_guest(p_token uuid, p_pickup uuid, p_name text) returns uuid
language plpgsql security definer set search_path = public as $$
declare k fc_pickups; me fc_members; m uuid; n text := left(trim(coalesce(p_name,'')), 30);
begin
  select * into k from fc_pickups where id = p_pickup;
  me := _fc_member(_uid(p_token), k.team_id);
  if n = '' then raise exception 'DATOS_INVALIDOS'; end if;
  select id into m from fc_members where team_id = k.team_id and lower(name) = lower(n) limit 1;
  if m is null then insert into fc_members(team_id, name, guest) values (k.team_id, n, true) returning id into m; end if;
  update fc_members set active = true where id = m;
  perform fc_pickup_join(p_token, p_pickup, m, 'va');
  return m;
end $$;

-- Armar los equipos: {"member_id": "oscuro" | "claro" | null}
create or replace function fc_pickup_sides(p_token uuid, p_pickup uuid, p_sides jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare k fc_pickups; me fc_members; e record;
begin
  select * into k from fc_pickups where id = p_pickup;
  me := _fc_member(_uid(p_token), k.team_id);
  for e in select * from jsonb_each_text(coalesce(p_sides, '{}'::jsonb)) loop
    update fc_pickup_players set side = case when e.value in ('oscuro','claro') then e.value end
    where pickup_id = p_pickup and member_id = e.key::uuid;
  end loop;
  update fc_pickups set organizer = me.id where id = p_pickup;
end $$;

-- Anotar un gol (o deshacerlo)
create or replace function fc_pickup_goal(p_token uuid, p_pickup uuid, p_member uuid, p_side text, p_undo uuid default null) returns void
language plpgsql security definer set search_path = public as $$
declare k fc_pickups; me fc_members;
begin
  select * into k from fc_pickups where id = p_pickup;
  me := _fc_member(_uid(p_token), k.team_id);
  if p_undo is not null then update fc_pickup_goals set undone = true where id = p_undo and pickup_id = p_pickup; return; end if;
  if p_side not in ('oscuro','claro') then raise exception 'DATOS_INVALIDOS'; end if;
  insert into fc_pickup_goals(pickup_id, member_id, side, created_by) values (p_pickup, p_member, p_side, me.id);
end $$;

-- Cargar el resultado final
create or replace function fc_pickup_finish(p_token uuid, p_pickup uuid, p_dark int, p_light int) returns void
language plpgsql security definer set search_path = public as $$
declare k fc_pickups; me fc_members;
begin
  select * into k from fc_pickups where id = p_pickup;
  me := _fc_member(_uid(p_token), k.team_id);
  update fc_pickups set score_dark = p_dark, score_light = p_light, status = 'jugada', finished_at = coalesce(finished_at, now()) where id = p_pickup;
end $$;

-- Votar la figura (48 h desde que se cargó el resultado)
create or replace function fc_pickup_vote(p_token uuid, p_pickup uuid, p_voted uuid) returns void
language plpgsql security definer set search_path = public as $$
declare k fc_pickups; me fc_members;
begin
  select * into k from fc_pickups where id = p_pickup;
  me := _fc_member(_uid(p_token), k.team_id);
  if k.status <> 'jugada' or k.finished_at < now() - interval '48 hours' then raise exception 'VOTACION_CERRADA'; end if;
  if p_voted = me.id then raise exception 'AUTOVOTO'; end if;
  insert into fc_pickup_votes(pickup_id, voter_id, voted_id) values (p_pickup, me.id, p_voted)
  on conflict (pickup_id, voter_id) do update set voted_id = excluded.voted_id;
end $$;

-- Quién pagó la cancha
create or replace function fc_pickup_paid(p_token uuid, p_pickup uuid, p_member uuid, p_paid boolean) returns void
language plpgsql security definer set search_path = public as $$
declare k fc_pickups; me fc_members;
begin
  select * into k from fc_pickups where id = p_pickup;
  me := _fc_member(_uid(p_token), k.team_id);
  update fc_pickup_players set paid = p_paid where pickup_id = p_pickup and member_id = p_member;
end $$;
