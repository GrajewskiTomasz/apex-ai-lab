-- smoke.sql
-- Cel: szybki sanity check na dane + komentarze pod NL->SQL

set serveroutput on
set pagesize 200
set linesize 200
whenever sqlerror exit failure rollback

prompt === AI_V_SALES_ORDER_LINES sample ===
select
  order_no,
  customer_name,
  status_desc,
  created_at,
  qty,
  amount_gross,
  currency_code
from ai_v_sales_order_lines
order by created_at desc, order_id desc, product_id
fetch first 5 rows only;

prompt === AI_V_SALES_ORDER_DAILY sample ===
select
  sales_date,
  status_desc,
  currency_code,
  orders_count,
  qty_sum,
  amount_gross_sum
from ai_v_sales_order_daily
order by sales_date desc, status_code, currency_code
fetch first 10 rows only;

prompt === V_SALES_ORDERS sample ===
select
  order_no,
  customer_name,
  status_desc,
  created_at,
  closed_at,
  amount_gross,
  lines_count,
  currency_code
from v_sales_orders
order by created_at desc, order_id desc
fetch first 5 rows only;

prompt === Check: column comments exist for AI_V_SALES_* ===
declare
  l_missing_cnt number;
begin
  select count(*)
    into l_missing_cnt
    from user_tab_columns c
    left join user_col_comments cc
      on cc.table_name = c.table_name
     and cc.column_name = c.column_name
   where c.table_name like 'AI\_V\_SALES\_%' escape '\'
     and (cc.comments is null or trim(cc.comments) is null);

  if l_missing_cnt > 0 then
    dbms_output.put_line('ERROR: Missing column comments in AI_V_SALES_*: ' || l_missing_cnt);

    for r in (
      select c.table_name, c.column_name
        from user_tab_columns c
        left join user_col_comments cc
          on cc.table_name = c.table_name
         and cc.column_name = c.column_name
       where c.table_name like 'AI\_V\_SALES\_%' escape '\'
         and (cc.comments is null or trim(cc.comments) is null)
       order by c.table_name, c.column_name
    ) loop
      dbms_output.put_line('  ' || r.table_name || '.' || r.column_name);
    end loop;

    raise_application_error(-20001, 'Smoke failed: missing column comments in AI_V_SALES_*');
  else
    dbms_output.put_line('OK: All AI_V_SALES_* columns have comments.');
  end if;
end;
/
