-- db/admin.sql
-- Uruchamiaj TYLKO tam, gdzie masz uprawnienia DBA/ADMIN.
-- Na Oracle Cloud APEX możesz to pominąć, żeby install.sql przechodził.

set define on
set serveroutput on
set feedback on
whenever sqlerror exit failure rollback

prompt === admin.sql start ===

-- Ustaw target user, jeśli chcesz nadać rolę komuś innemu (np. user ORDS/integracji)
-- Przykład:
-- define TARGET_USER = MY_APP_USER
-- Jeśli nie ustawisz, grant roli do usera będzie pominięty.
define TARGET_USER = ""

prompt === 1) Create role (idempotent) ===
declare
begin
  execute immediate 'create role AI_QUERY_ROLE';
  dbms_output.put_line('OK: created role AI_QUERY_ROLE');
exception
  when others then
    if sqlcode = -1921 then
      dbms_output.put_line('OK: role AI_QUERY_ROLE already exists');
    else
      dbms_output.put_line('WARN: create role skipped: ' || sqlerrm);
    end if;
end;
/

prompt === 2) Grants to role (views + packages) ===
declare
  procedure safe_exec(p_sql varchar2) is
  begin
    execute immediate p_sql;
    dbms_output.put_line('OK: ' || p_sql);
  exception
    when others then
      dbms_output.put_line('WARN: ' || p_sql || ' -> ' || sqlerrm);
  end;
begin
  -- Whitelist views
  safe_exec('grant select on AI_V_SALES_ORDER_LINES to AI_QUERY_ROLE');
  safe_exec('grant select on AI_V_SALES_ORDER_DAILY to AI_QUERY_ROLE');

  -- Packages (jak już istnieją w schemacie)
  safe_exec('grant execute on AI_LOG to AI_QUERY_ROLE');
  safe_exec('grant execute on AI_SQL_GUARD to AI_QUERY_ROLE');
  safe_exec('grant execute on AI_SQL_EXEC to AI_QUERY_ROLE');
  safe_exec('grant execute on AI_NL2SQL to AI_QUERY_ROLE');
end;
/

prompt === 3) Grant role to target user (optional) ===
declare
  l_user varchar2(128) := upper('&&TARGET_USER');
  procedure safe_exec(p_sql varchar2) is
  begin
    execute immediate p_sql;
    dbms_output.put_line('OK: ' || p_sql);
  exception
    when others then
      dbms_output.put_line('WARN: ' || p_sql || ' -> ' || sqlerrm);
  end;
begin
  if l_user is null or l_user = '' then
    dbms_output.put_line('INFO: TARGET_USER not set, skipping role grant to user.');
  else
    safe_exec('grant AI_QUERY_ROLE to ' || dbms_assert.simple_sql_name(l_user));
  end if;
end;
/

prompt === admin.sql done ===
commit;
