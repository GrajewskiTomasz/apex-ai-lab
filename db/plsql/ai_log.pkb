create or replace package body ai_log as
  function new_request_id return varchar2 is
  begin
    return lower(rawtohex(sys_guid()));
  end;

  procedure write(
    p_request_id   in varchar2,
    p_app_user     in varchar2,
    p_question     in varchar2,
    p_view_used    in varchar2,
    p_sql_text     in clob,
    p_guard_status in varchar2,
    p_exec_status  in varchar2,
    p_row_count    in number,
    p_llm_ms       in number,
    p_exec_ms      in number,
    p_err_code     in number,
    p_err_msg      in varchar2
  ) is
  begin
    insert into ai_nl2sql_log(
      request_id, app_user, question, view_used, sql_text,
      guard_status, exec_status, row_count, llm_ms, exec_ms, err_code, err_msg
    ) values (
      p_request_id, p_app_user, substr(p_question,1,4000), p_view_used, p_sql_text,
      p_guard_status, p_exec_status, p_row_count, p_llm_ms, p_exec_ms, p_err_code, substr(p_err_msg,1,4000)
    );
  end;
end ai_log;
/
