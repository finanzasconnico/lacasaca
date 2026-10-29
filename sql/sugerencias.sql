-- La Casaca: sugerencias del plantel en la pizarra. Se puede correr más de una vez.
-- Cualquiera del plantel deja un comentario o propone su equipo (formación y quién va en cada lugar);
-- el DT y los ayudantes las ven al lado de la pizarra, las usan o las archivan. El DT lo puede apagar.

alter table fc_teams add column if not exists board_suggest boolean not null default true;

create table if not exists fc_board_tips (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references fc_teams(id) on delete cascade,
  lineup_id uuid references fc_lineups(id) on delete set null,
  member_id uuid not null references fc_members(id) on delete cascade,
  body text not null default '',
  formation text,
  slots jsonb,
  likes uuid[] not null default '{}',
  status text not null default 'abierta' check (status in ('abierta', 'usada', 'archivada')),
  reply text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists fc_board_tips_team on fc_board_tips(team_id, created_at desc);
alter table fc_board_tips enable row level security;

create or replace function fc_board_tips(p_token uuid, p_team uuid) returns json
language plpgsql security definer set search_path = public as $$
declare me fc_members := _fc_member(_uid(p_token), p_team);
begin
  return (select coalesce(json_agg(json_build_object('id', b.id, 'lineup_id', b.lineup_id, 'member_id', b.member_id, 'body', b.body,
      'formation', b.formation, 'slots', b.slots, 'likes', cardinality(b.likes), 'liked', me.id = any(b.likes),
      'status', b.status, 'reply', b.reply, 'created_at', b.created_at, 'updated_at', b.updated_at) order by b.created_at desc), '[]'::json)
    from (select * from fc_board_tips where team_id = p_team and (status = 'abierta' or updated_at > now() - interval '30 days')
          order by created_at desc limit 60) b);
end $$;

create or replace function fc_board_tip_save(p_token uuid, p_team uuid, p_lineup uuid, p_body text, p_formation text, p_slots jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare me fc_members := _fc_member(_uid(p_token), p_team); t fc_teams; v_id uuid; v_body text := left(trim(coalesce(p_body, '')), 300);
begin
  select * into t from fc_teams where id = p_team;
  if not t.board_suggest and me.role not in ('dt', 'ayudante') then raise exception 'NO_PERMITIDO'; end if;
  if v_body = '' and p_slots is null then raise exception 'DATOS_INVALIDOS'; end if;
  if p_slots is not null and (jsonb_typeof(p_slots) <> 'array' or jsonb_array_length(p_slots) > 12) then raise exception 'DATOS_INVALIDOS'; end if;
  if p_lineup is not null and not exists (select 1 from fc_lineups where id = p_lineup and team_id = p_team) then p_lineup := null; end if;
  if (select count(*) from fc_board_tips where member_id = me.id and status = 'abierta') >= 10 then raise exception 'DEMASIADAS'; end if;
  insert into fc_board_tips(team_id, lineup_id, member_id, body, formation, slots)
  values (p_team, p_lineup, me.id, v_body, left(p_formation, 12), p_slots) returning id into v_id;
  perform _fc_push(
    array(select distinct m.user_id from fc_members m where m.team_id = p_team and m.active and m.user_id is not null
          and m.role in ('dt', 'ayudante') and m.id <> me.id),
    '💡 ' || me.name || ' sugirió en la pizarra',
    case when v_body <> '' then left(v_body, 140) else 'Propuso un equipo' || coalesce(' (' || p_formation || ')', '') || '. Miralo al lado de la pizarra.' end,
    './?team=' || p_team || '&tab=pizarra', 'pizarra-' || p_team);
  return v_id;
end $$;

create or replace function fc_board_tip_like(p_token uuid, p_tip uuid) returns void
language plpgsql security definer set search_path = public as $$
declare b fc_board_tips; me fc_members;
begin
  select * into b from fc_board_tips where id = p_tip;
  if b.id is null then raise exception 'NO_EXISTE'; end if;
  me := _fc_member(_uid(p_token), b.team_id);
  update fc_board_tips set likes = case when me.id = any(likes) then array_remove(likes, me.id) else likes || me.id end where id = p_tip;
end $$;

-- DT y ayudantes: usar, archivar o reabrir (con respuesta opcional). El autor puede retirar la suya.
create or replace function fc_board_tip_status(p_token uuid, p_tip uuid, p_status text, p_reply text default null) returns void
language plpgsql security definer set search_path = public as $$
declare b fc_board_tips; me fc_members; author uuid;
begin
  select * into b from fc_board_tips where id = p_tip;
  if b.id is null then raise exception 'NO_EXISTE'; end if;
  me := _fc_member(_uid(p_token), b.team_id);
  if p_status not in ('abierta', 'usada', 'archivada') then raise exception 'DATOS_INVALIDOS'; end if;
  if me.role not in ('dt', 'ayudante') and not (me.id = b.member_id and p_status = 'archivada') then raise exception 'NO_PERMITIDO'; end if;
  update fc_board_tips set status = p_status, updated_at = now(),
    reply = case when p_reply is not null then nullif(left(trim(p_reply), 200), '') else reply end
  where id = p_tip;
  if me.id <> b.member_id and (p_status = 'usada' or coalesce(trim(p_reply), '') <> '') then
    select user_id into author from fc_members where id = b.member_id;
    perform _fc_push(array[author]::uuid[],
      case when p_status = 'usada' then '✅ ' || me.name || ' usó tu sugerencia' else '💬 ' || me.name || ' te respondió en la pizarra' end,
      coalesce(nullif(left(trim(p_reply), 140), ''), 'Mirala en la pizarra.'),
      './?team=' || b.team_id || '&tab=pizarra', 'pizarra-tip-' || b.id);
  end if;
end $$;

-- fc_team devuelve el ajuste y Ajustes lo guarda
do $$ declare d text; begin
  d := pg_get_functiondef('fc_team'::regproc);
  if position('board_suggest' in d) = 0 then
    d := replace(d, '''ratings_public'', t.ratings_public,', '''ratings_public'', t.ratings_public, ''board_suggest'', t.board_suggest,');
    execute d;
  end if;
  d := pg_get_functiondef('fc_team_settings'::regproc);
  if position('board_suggest' in d) = 0 then
    d := replace(d, '    ratings_public = coalesce((p->>''ratings_public'')::boolean, ratings_public),',
      '    ratings_public = coalesce((p->>''ratings_public'')::boolean, ratings_public),
    board_suggest = coalesce((p->>''board_suggest'')::boolean, board_suggest),');
    execute d;
  end if;
end $$;
