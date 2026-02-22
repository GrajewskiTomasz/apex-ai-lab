create or replace package ai_sql_exec as
  function run(
    p_sql   in clob,
    p_limit in number default 50
  ) return sys_refcursor;
end ai_sql_exec;
/
