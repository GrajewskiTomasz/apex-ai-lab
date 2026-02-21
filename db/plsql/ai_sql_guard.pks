create or replace package ai_sql_guard as
  procedure validate(
    p_sql_in    in  clob,
    p_limit     in  number,
    o_sql_out   out clob,
    o_status    out varchar2,
    o_reason    out varchar2,
    o_view_used out varchar2
  );
end ai_sql_guard;
/
