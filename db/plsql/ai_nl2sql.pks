create or replace package ai_nl2sql as
  function generate(
    p_question in varchar2,
    p_limit    in number default 50
  ) return clob;

  procedure run(
    p_question   in  varchar2,
    p_limit      in  number default 50,
    p_app_user   in  varchar2 default null,
    o_request_id out varchar2,
    o_sql        out clob,
    o_rc         out sys_refcursor
  );
end ai_nl2sql;
/
