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
    l_sql_v   varchar2(32767);
    l_u       varchar2(32767);
    l_limit   number := norm_limit(p_limit);
    l_cur     integer;
    l_view    varchar2(128);
    l_occ     number := 1;
    l_found   number := 0;
    l_enabled number;
  begin
    o_sql_out := null;
    o_status := 'ERROR';
    o_reason := null;
    o_view_used := null;

    if p_sql_in is null then
      o_status := 'BLOCKED';
      o_reason := 'EMPTY_SQL';
      return;
    end if;

    l_sql_v := dbms_lob.substr(p_sql_in, 32767, 1);
    l_sql_v := replace(l_sql_v, chr(65279), ''); -- BOM
    l_sql_v := trim(l_sql_v);

    if l_sql_v is null then
      o_status := 'BLOCKED';
      o_reason := 'EMPTY_SQL';
      return;
    end if;

    if substr(l_sql_v, -1) = ';' then
      l_sql_v := substr(l_sql_v, 1, length(l_sql_v)-1);
    end if;

    l_u := upper(l_sql_v);

    if not (l_u like 'SELECT%' or l_u like 'WITH%') then
    o_status := 'BLOCKED';
    o_reason := 'ONLY_SELECT_ALLOWED';
    return;
    end if;

    l_u := upper(l_sql_v);

    if regexp_like(l_u,'(^|[^A-Z0-9_])(INSERT|UPDATE|DELETE|MERGE|DROP|ALTER|CREATE|TRUNCATE|GRANT|REVOKE|COMMIT|ROLLBACK|BEGIN|DECLARE)([^A-Z0-9_]|$)') then
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

    if regexp_like(l_u, '\bSALES_[A-Z0-9_]+\b') or regexp_like(l_u, '\bV_SALES_[A-Z0-9_]+\b') then
      o_status := 'BLOCKED';
      o_reason := 'ONLY_AI_VIEWS_ALLOWED';
      return;
    end if;

    loop
      l_view := regexp_substr(l_u, 'AI_V_SALES_[A-Z0-9_]+', 1, l_occ);
      exit when l_view is null;

      l_occ := l_occ + 1;
      l_found := 1;
      o_view_used := l_view;

      select count(*)
        into l_enabled
        from ai_nl2sql_whitelist
       where view_name = l_view
         and enabled_yn = 'Y';

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

    if instr(l_u, 'FETCH FIRST') = 0 then
      o_sql_out := to_clob(rtrim(l_sql_v) || ' fetch first ' || to_char(l_limit) || ' rows only');
    else
      o_sql_out := to_clob(rtrim(l_sql_v));
    end if;

    l_cur := dbms_sql.open_cursor;
    begin
      dbms_sql.parse(l_cur, o_sql_out, dbms_sql.native);
    exception
      when others then
        o_status := 'BLOCKED';
        o_reason := 'PARSE_ERROR: ' || substr(sqlerrm, 1, 900);
        if dbms_sql.is_open(l_cur) then dbms_sql.close_cursor(l_cur); end if;
        return;
    end;
    dbms_sql.close_cursor(l_cur);

    o_status := 'OK';
    o_reason := 'OK';
  end validate;
end ai_sql_guard;
/
