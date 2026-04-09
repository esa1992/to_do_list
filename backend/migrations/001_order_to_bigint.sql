-- Клиент использует order = millisecondsSinceEpoch; int32 в PostgreSQL слишком мал.
-- Выполни в Supabase SQL Editor один раз, если таблицы уже созданы со старой схемой.

alter table groups alter column "order" type bigint using "order"::bigint;
alter table tasks alter column "order" type bigint using "order"::bigint;
