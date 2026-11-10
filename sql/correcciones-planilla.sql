-- La Casaca: correcciones a la planilla oficial (ya aplicado en la base el 10/11).
-- fc_sheet_fixes: para un partido y un jugador de la planilla, a quién se le acredita (member_id) o a nadie (null).
-- _fc_league_sheet_stats las respeta, así la próxima sincronización con el torneo no las pisa.
--   31/10 vs Amanita: "Agustin Simon" en la planilla era Julian; "Francisco Folino" (el 1) era Joni.
--   Folino solo jugó contra Bidón: se sacan 05/09, 12/09 y 19/09.
-- También: ADZ unificado en "Bari (ADZ)" (se le pasó la cuenta y la confirmación), y "fara" del 07/11 era Panda (5).
create table if not exists fc_sheet_fixes (team_id uuid not null, match_id uuid not null, ext_player_id int not null, member_id uuid, note text, primary key (match_id, ext_player_id));
alter table fc_sheet_fixes enable row level security;
-- Para agregar una corrección:
-- insert into fc_sheet_fixes(team_id, match_id, ext_player_id, member_id, note) values (...);
-- y después: select _fc_league_sheet_stats(team_id) ...
