create or replace package ai_log as
  function new_request_id return varchar2;

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
  );
end ai_log;
/
