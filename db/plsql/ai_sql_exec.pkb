create or replace package body ai_sql_exec as
  function norm_limit(p_limit number) return number is
  begin
    return least(greatest(nvl(p_limit, 50), 1), 500);
  end;

  function strip_semicolon(p_sql clob) return clob is
    l_sql clob := trim(p_sql);
  begin
    if l_sql is not null and substr(l_sql, -1) = ';' then
      l_sql := substr(l_sql, 1, length(l_sql)-1);
    end if;
    return l_sql;
  end;

  function run(
    p_sql   in clob,
    p_limit in number default 50
  ) return sys_refcursor is
    l_rc sys_refcursor;
    l_sql clob;
    l_wrapped clob;
    l_limit number := norm_limit(p_limit);
  begin
    l_sql := strip_semicolon(p_sql);

    -- zawsze wymuś limit jeszcze raz na zewnątrz
    l_wrapped := 'select * from (' || l_sql || ') fetch first ' || to_char(l_limit) || ' rows only';

    open l_rc for l_wrapped;
    return l_rc;
  end run;
end ai_sql_exec;
/
