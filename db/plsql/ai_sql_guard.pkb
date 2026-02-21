create or replace package body ai_sql_guard as
  function norm_limit(p_limit number) return number is
  begin
    return least(greatest(nvl(p_limit, 50), 1), 500);
  end;

  procedure validate(
    p_sql_in    in  clob,
    p_limit     in  number,
    o_sql_out   out clob,
    o_status    out varchar2,
    o_reason    out varchar2,
    o_view_used out varchar2
  ) is
    l_sql      clob;
    l_u        clob;
    l_limit    number := norm_limit(p_limit);
    l_cur      integer;
    l_view     varchar2(128);
    l_occ      number := 1;
    l_found    number := 0;
    l_enabled  number;
  begin
    o_sql_out := null;
    o_status := 'ERROR';
    o_reason := null;
    o_view_used := null;

    l_sql := trim(p_sql_in);

    if l_sql is null then
      o_status := 'BLOCKED';
      o_reason := 'EMPTY_SQL';
      return;
    end if;

    -- usuń trailing ';'
    if substr(l_sql, -1) = ';' then
      l_sql := substr(l_sql, 1, length(l_sql)-1);
    end if;

    l_u := upper(l_sql);

    if not regexp_like(l_u, '^\s*SELECT\b') then
      o_status := 'BLOCKED';
      o_reason := 'ONLY_SELECT_ALLOWED';
      return;
    end if;

    if regexp_like(l_u, '\b(INSERT|UPDATE|DELETE|MERGE|DROP|ALTER|CREATE|TRUNCATE|GRANT|REVOKE|COMMIT|ROLLBACK|BEGIN|DECLARE)\b') then
      o_status := 'BLOCKED';
      o_reason := 'FORBIDDEN_KEYWORD';
      return;
    end if;

    if regexp_like(l_u, '\b(DBMS_|UTL_|HTTPURITYPE|ORDS|APEX_)\b') then
      o_status := 'BLOCKED';
      o_reason := 'FORBIDDEN_PACKAGE';
      return;
    end if;

    if regexp_like(l_u, '\b(DBA_|ALL_USERS|USER_USERS|V\$_|GV\$_)\b') then
      o_status := 'BLOCKED';
      o_reason := 'FORBIDDEN_DICTIONARY';
      return;
    end if;

    -- twardo blokuj dostęp do tabel SALES_* i widoków V_SALES_* (v1 whitelist tylko AI_V_*)
    if regexp_like(l_u, '\bSALES_[A-Z0-9_]+\b') or regexp_like(l_u, '\bV_SALES_[A-Z0-9_]+\b') then
      o_status := 'BLOCKED';
      o_reason := 'ONLY_AI_VIEWS_ALLOWED';
      return;
    end if;

    -- sprawdź, czy wszystkie wystąpienia AI_V_SALES_* są w whitelist
    loop
      l_view := regexp_substr(l_u, 'AI_V_SALES_[A-Z0-9_]+', 1, l_occ);
      exit when l_view is null;

      l_occ := l_occ + 1;
      l_found := 1;
      o_view_used := l_view; -- ostatni, wystarczy do logu v0

      begin
        select count(*)
          into l_enabled
          from ai_nl2sql_whitelist
         where view_name = l_view
           and enabled_yn = 'Y';
      exception
        when others then
          l_enabled := 0;
      end;

      if l_enabled = 0 then
        o_status := 'BLOCKED';
        o_reason := 'VIEW_NOT_WHITELISTED: ' || l_view;
        return;
      end if;
    end loop;

    if l_found = 0 then
      o_status := 'BLOCKED';
      o_reason := 'NO_AI_VIEW_USED';
      return;
    end if;

    -- dołóż limit jeśli nie ma FETCH FIRST
    if not regexp_like(l_u, '\bFETCH\s+FIRST\s+\d+\s+ROWS\s+ONLY\b') then
      o_sql_out := l_sql || ' fetch first ' || to_char(l_limit) || ' rows only';
    else
      o_sql_out := l_sql;
    end if;

    -- parse (twardy sanity)
    l_cur := dbms_sql.open_cursor;
    begin
      dbms_sql.parse(l_cur, o_sql_out, dbms_sql.native);
    exception
      when others then
        o_status := 'BLOCKED';
        o_reason := 'PARSE_ERROR: ' || substr(sqlerrm, 1, 900);
        dbms_sql.close_cursor(l_cur);
        return;
    end;
    dbms_sql.close_cursor(l_cur);

    o_status := 'OK';
    o_reason := 'OK';
  end validate;
end ai_sql_guard;
/
