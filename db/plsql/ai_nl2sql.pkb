create or replace package body ai_nl2sql as
  function norm_limit(p_limit number) return number is
  begin
    return least(greatest(nvl(p_limit, 50), 1), 500);
  end;

  function pick_status_code(p_q varchar2) return varchar2 is
    l_q varchar2(4000) := lower(nvl(p_q,''));
  begin
    if instr(l_q, 'new') > 0 or instr(l_q, 'nowe') > 0 then return 'NEW'; end if;
    if instr(l_q, 'paid') > 0 or instr(l_q, 'oplac') > 0 then return 'PAID'; end if;
    if instr(l_q, 'cancel') > 0 or instr(l_q, 'anul') > 0 then return 'CANCELLED'; end if;
    if instr(l_q, 'ship') > 0 or instr(l_q, 'wysyl') > 0 then return 'SHIPPED'; end if;
    if instr(l_q, 'closed') > 0 or instr(l_q, 'zamkn') > 0 then return 'CLOSED'; end if;
    return null;
  end;

  function pick_currency(p_q varchar2) return varchar2 is
    l_q varchar2(4000) := lower(nvl(p_q,''));
  begin
    if instr(l_q, 'pln') > 0 then return 'PLN'; end if;
    if instr(l_q, 'eur') > 0 then return 'EUR'; end if;
    if instr(l_q, 'usd') > 0 then return 'USD'; end if;
    return null;
  end;

  function pick_date_literal(p_q varchar2) return varchar2 is
    l_date varchar2(10);
  begin
    -- wyciągnij YYYY-MM-DD jeśli jest w pytaniu
    l_date := regexp_substr(p_q, '(20[0-9]{2}-[0-9]{2}-[0-9]{2})', 1, 1);
    return l_date;
  end;

  function generate(
    p_question in varchar2,
    p_limit    in number default 50
  ) return clob is
    l_q       varchar2(4000) := lower(nvl(p_question,''));
    l_limit   number := norm_limit(p_limit);
    l_view    varchar2(128);
    l_sql     clob;
    l_status  varchar2(20);
    l_curr    varchar2(3);
    l_date    varchar2(10);
    l_where   varchar2(2000) := ' where 1=1 ';
    l_order   varchar2(2000) := '';
    l_json    clob;
  begin
    -- wybór widoku (stub)
    if instr(l_q, 'pozyc') > 0 or instr(l_q, 'produkt') > 0 or instr(l_q, 'sku') > 0 then
      l_view := 'AI_V_SALES_ORDER_LINES';
    else
      l_view := 'AI_V_SALES_ORDER_DAILY';
    end if;

    l_status := pick_status_code(l_q);
    l_curr   := pick_currency(l_q);
    l_date   := pick_date_literal(l_q);

    if l_view = 'AI_V_SALES_ORDER_LINES' then
      if l_status is not null then l_where := l_where || ' and status_code = ''' || l_status || ''' '; end if;
      if l_curr is not null then l_where := l_where || ' and currency_code = ''' || l_curr || ''' '; end if;
      if l_date is not null then l_where := l_where || ' and trunc(created_at) = date ''' || l_date || ''' '; end if;

      if instr(l_q, 'naj') > 0 or instr(l_q, 'top') > 0 then
        l_order := ' order by amount_gross desc ';
      else
        l_order := ' order by created_at desc, order_id desc ';
      end if;

      l_sql :=
        'select ' ||
        ' order_id, order_no, customer_id, customer_code, customer_name, segment_desc,' ||
        ' created_at, closed_at, status_code, status_desc, currency_code,' ||
        ' product_id, sku, product_name, category_desc,' ||
        ' qty, amount_net, amount_gross' ||
        ' from AI_V_SALES_ORDER_LINES' || l_where || l_order ||
        ' fetch first ' || to_char(l_limit) || ' rows only';

    else
      if l_status is not null then l_where := l_where || ' and status_code = ''' || l_status || ''' '; end if;
      if l_curr is not null then l_where := l_where || ' and currency_code = ''' || l_curr || ''' '; end if;
      if l_date is not null then l_where := l_where || ' and sales_date = date ''' || l_date || ''' '; end if;

      if instr(l_q, 'naj') > 0 or instr(l_q, 'top') > 0 then
        l_order := ' order by amount_gross_sum desc ';
      else
        l_order := ' order by sales_date desc, status_code, currency_code ';
      end if;

      l_sql :=
        'select ' ||
        ' sales_date, status_code, status_desc, currency_code,' ||
        ' orders_count, qty_sum, amount_net_sum, amount_gross_sum' ||
        ' from AI_V_SALES_ORDER_DAILY' || l_where || l_order ||
        ' fetch first ' || to_char(l_limit) || ' rows only';
    end if;

    select json_object(
             'view_used' value l_view,
             'limit'     value l_limit,
             'sql'       value l_sql,
             'llm_ms'    value 0
             returning clob
           )
      into l_json
      from dual;

    return l_json;
  end generate;

  procedure run(
    p_question   in  varchar2,
    p_limit      in  number default 50,
    p_app_user   in  varchar2 default null,
    o_request_id out varchar2,
    o_sql        out clob,
    o_rc         out sys_refcursor
  ) is
    l_req      varchar2(32);
    l_gen      clob;
    l_view     varchar2(128);
    l_sql_in   clob;
    l_sql_out  clob;
    l_gstat    varchar2(30);
    l_greason  varchar2(1000);
    l_emsg     varchar2(4000);
    l_err      number;
    t0         number;
    t1         number;
    l_exec_ms  number := null;
  begin
    l_req := ai_log.new_request_id;
    o_request_id := l_req;

    l_gen := generate(p_question, p_limit);

    l_view := json_value(l_gen, '$.view_used');
    l_sql_in := json_value(l_gen, '$.sql' returning clob);

    ai_sql_guard.validate(
      p_sql_in    => l_sql_in,
      p_limit     => p_limit,
      o_sql_out   => l_sql_out,
      o_status    => l_gstat,
      o_reason    => l_greason,
      o_view_used => l_view
    );

    if l_gstat <> 'OK' then
      ai_log.write(
        p_request_id   => l_req,
        p_app_user     => p_app_user,
        p_question     => p_question,
        p_view_used    => l_view,
        p_sql_text     => l_sql_in,
        p_guard_status => l_gstat || ':' || l_greason,
        p_exec_status  => 'BLOCKED',
        p_row_count    => null,
        p_llm_ms       => 0,
        p_exec_ms      => null,
        p_err_code     => null,
        p_err_msg      => null
      );
      commit;
      raise_application_error(-20002, 'NL->SQL blocked: ' || l_greason);
    end if;

    t0 := dbms_utility.get_time;
    begin
      o_rc := ai_sql_exec.run(l_sql_out, p_limit);
      t1 := dbms_utility.get_time;
      l_exec_ms := (t1 - t0) * 10;
      o_sql := l_sql_out;

      ai_log.write(
        p_request_id   => l_req,
        p_app_user     => p_app_user,
        p_question     => p_question,
        p_view_used    => l_view,
        p_sql_text     => l_sql_out,
        p_guard_status => 'OK',
        p_exec_status  => 'OK',
        p_row_count    => null,
        p_llm_ms       => 0,
        p_exec_ms      => l_exec_ms,
        p_err_code     => null,
        p_err_msg      => null
      );
      commit;
    exception
      when others then
        t1 := dbms_utility.get_time;
        l_exec_ms := (t1 - t0) * 10;
        l_err := sqlcode;
        l_emsg := sqlerrm;

        ai_log.write(
          p_request_id   => l_req,
          p_app_user     => p_app_user,
          p_question     => p_question,
          p_view_used    => l_view,
          p_sql_text     => l_sql_out,
          p_guard_status => 'OK',
          p_exec_status  => 'ERROR',
          p_row_count    => null,
          p_llm_ms       => 0,
          p_exec_ms      => l_exec_ms,
          p_err_code     => l_err,
          p_err_msg      => l_emsg
        );
        commit;
        raise;
    end;
  end run;
end ai_nl2sql;
/
