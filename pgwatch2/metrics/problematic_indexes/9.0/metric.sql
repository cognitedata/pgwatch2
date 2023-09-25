select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  *
from (
select
  quote_ident(sui.schemaname)||'.'||quote_ident(sui.indexrelname) as index_full_name,
  sui.idx_scan,
  i.indisvalid::int,
  coalesce(pg_relation_size(sui.indexrelid), 0) as index_size_b
from
  pg_stat_user_indexes sui
  join pg_index i on i.indexrelid = sui.indexrelid
where not sui.schemaname like E'pg\\_temp%'
and (not indisvalid or idx_scan = 0)
and not exists (select * from pg_locks where relation = sui.relid and mode = 'AccessExclusiveLock')
) x
where (indisvalid = 0 or index_size_b > 100*1024^2) /* >100MB */
order by index_size_b desc
limit 100;
