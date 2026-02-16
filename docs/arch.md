# arch

## 1. Cel i zakres v1
1. Feature: NL→SQL dla obszaru sprzedaż/zamówienia.
2. NL→SQL działa wyłącznie na whitelist widoków `AI_V_SALES_*`.
3. Dozwolone są tylko zapytania `SELECT`.
4. Każde zapytanie ma wymuszony limit wierszy i timeout.
5. Wynik ma być powtarzalny: te same wejścia, podobne wyjścia (format i ograniczenia).

## 2. Kontekst techniczny
1. Oracle Database 19c.
2. APEX 20.x+.
3. ORDS na Tomcat (APEX REST/DB REST jako warstwa integracji, jeśli potrzebne).
4. LLM dostępny przez REST (bramka po stronie serwera, nie z przeglądarki).

## 3. Komponenty
### 3.1 APEX UI
1. Strona “NL→SQL”: pole pytania, podgląd SQL, wynik, historia, przycisk “popraw”.
2. Tryb “strict” domyślnie: user widzi wynik i krótką notkę, SQL opcjonalnie.

### 3.2 PL/SQL (kontrakty paczek)
1. `ai_llm`
   1) odpowiedzialność: call REST do LLM
   2) wejście: JSON z promptem i kontekstem
   3) wyjście: JSON odpowiedzi modelu (bez wykonywania SQL)
2. `ai_nl2sql`
   1) odpowiedzialność: budowa kontekstu na bazie metadanych whitelisty + składanie promptu
   2) wejście: pytanie użytkownika, limit
   3) wyjście: JSON: `sql`, `binds`, `confidence`, `notes`, `warnings`
3. `ai_sql_guard`
   1) odpowiedzialność: walidacja wygenerowanego SQL
   2) reguły: tylko SELECT, tylko AI_V_SALES_*, limit, zakazane konstrukcje
4. `ai_sql_exec`
   1) odpowiedzialność: wykonanie zapytania po guardzie z bindami i limitami
5. `ai_log`
   1) odpowiedzialność: log i metryki (bez sekretów i bez danych wrażliwych)

### 3.3 Warstwa danych
Źródło: `sales_seed.sql`

Obiekty źródłowe (tabele)
1. Słowniki
   1) `SALES_LU_SEGMENT(segment_code, segment_desc)`
   2) `SALES_LU_COUNTRY(country_code, country_name)`
   3) `SALES_LU_ORDER_STATUS(status_code, status_desc)` mapowanie: NEW/PAID/CANCELLED/SHIPPED/CLOSED
   4) `SALES_LU_CURRENCY(currency_code, currency_name)` PLN/EUR/USD
   5) `SALES_LU_PRODUCT_CATEGORY(category_code, category_desc)`
2. Encje
   1) `SALES_CUSTOMERS(customer_id, customer_code, customer_name, segment_code, city, country_code, created_at, is_active)`
   2) `SALES_PRODUCTS(product_id, sku, product_name, category_code, is_active)`
   3) `SALES_ORDERS(order_id, order_no, customer_id, created_at, closed_at, status_code, currency_code, notes)`
   4) `SALES_ORDER_LINES(line_id, order_id, product_id, qty, unit_price_net, tax_rate, amount_net, amount_gross)`

Widoki encji
1. `V_SALES_CUSTOMERS`
   1) kolumny: customer_id, customer_code, customer_name, segment_code, segment_desc, city, country_code, country_name, created_at, is_active
   2) cel: jeden “bezpieczny” obraz klienta do joinów i filtrów
2. `V_SALES_ORDERS`
   1) kolumny: order_id, order_no, customer_id, customer_code, customer_name, created_at, closed_at, status_code, status_desc, currency_code, amount_net, amount_gross, lines_count
   2) cel: nagłówek zamówienia + sumy z pozycji
   3) `notes` świadomie pominięte (ryzyko wolnego tekstu)

Widoki raportowe (whitelist NL→SQL)
1. `AI_V_SALES_ORDER_LINES`
   1) jeden wiersz = jedna pozycja zamówienia z dołączonym zamówieniem, klientem, produktem i słownikami
   2) kolumny: order_id, order_no, customer_id, customer_code, customer_name, segment_desc, created_at, closed_at, status_code, status_desc, currency_code, product_id, sku, product_name, category_desc, qty, amount_net, amount_gross
2. `AI_V_SALES_ORDER_DAILY`
   1) agregacja per dzień i status
   2) kolumny: sales_date, status_code, status_desc, currency_code, orders_count, qty_sum, amount_net_sum, amount_gross_sum
   3) sales_date = TRUNC(created_at)

Dane testowe (seed)
1. 5 klientów, 6 produktów, 8 zamówień, 20 pozycji.
2. Rozkład statusów i dat jest pod raportowanie per dzień, per status, per klient, per produkt.

## 4. Przepływ end-to-end
1. User wpisuje pytanie w APEX.
2. `ai_nl2sql` buduje kontekst:
   1) bierze metadane wyłącznie dla `AI_V_SALES_*` (nazwy kolumn, typy, komentarze)
   2) dopina reguły “tylko SELECT”, “tylko whitelista”, “limit obowiązkowy”
3. `ai_llm` wysyła prompt do LLM.
4. LLM zwraca JSON z SQL i bindami.
5. `ai_sql_guard` waliduje SQL:
   1) statement type = SELECT
   2) referencje tylko do `AI_V_SALES_*`
   3) brak zakazanych słów/konstrukcji
   4) jest limit, a jeśli nie ma, jest dopinany
6. `ai_sql_exec` wykonuje SQL:
   1) tylko bindy, żadnego sklejania stringów
   2) timeout i max rows
7. `ai_log` zapisuje metryki i status.
8. Wynik wraca do UI.

## 5. Zasady semantycznej whitelisty
1. Do NL→SQL dopuszczamy tylko widoki `AI_V_SALES_*`.
2. W AI widokach trzymamy:
   1) klucze encji: customer_id, order_id, product_id
   2) pola biznesowe do filtrów i grupowań (daty, status, waluta)
   3) pola pod agregacje: qty, amount_net, amount_gross
3. Nie dopuszczamy:
   1) wolnego tekstu (np. notes, opisy wewnętrzne)
   2) PII, jeżeli kiedyś się pojawi (mail, telefon, adres szczegółowy)
4. Nazewnictwo:
   1) daty: created_at, closed_at
   2) status: status_code, status_desc
   3) waluta: currency_code
5. Join keys mają zawsze być kolumnami w widoku, nawet jeśli “normalnie nie pokazujesz”.

## 6. Guardrails i bezpieczeństwo
1. SQL
   1) tylko SELECT
   2) zakaz: INSERT/UPDATE/DELETE/MERGE/DDL, UNION ALL do obejść limitów, dbms_*, utl_*, dblink, hinty
2. Whitelist obiektów
   1) tylko `AI_V_SALES_ORDER_LINES` i `AI_V_SALES_ORDER_DAILY` (v1)
3. Limity
   1) wymuszony `FETCH FIRST :N ROWS ONLY` lub równoważny mechanizm
   2) max N po stronie serwera (max rows 200)
4. Wykonanie
   1) tylko bindy
   2) timeout na call LLM - 10s i na wykonanie SQL - 2s
5. Błędy
   1) user dostaje krótki komunikat “zapytanie zablokowane przez zasady”
   2) szczegóły lecą do logów technicznych

## 7. Obserwowalność
1. Logujemy:
   1) pytanie, wygenerowany SQL, bindy (bez wrażliwych wartości), czas LLM, czas guard, czas exec
   2) status: ok, blocked, error
   3) rowcount
   4) app_id, page_id, user
2. Nie logujemy:
   1) sekretów, tokenów
   2) pełnych wyników danych
3. Korelacja:
   1) request_id dla całego flow (UI → LLM → guard → exec)

## 8. Ewaluacja jakości
1. Dataset pytań dla obszaru SALES:
   1) pytanie
   2) oczekiwany wynik (np. asercje: “ma zwrócić >0”, “ma być per day”, “ma filtrować status”)
2. Batch run:
   1) odpalasz wszystkie pytania po zmianie promptu albo widoków
   2) zapisujesz pass rate i typy błędów
3. Metryki:
   1) pass rate
   2) blocked rate (guard)
   3) średni czas LLM i SQL

## 9. Deployment między środowiskami
1. Dev
   1) odpal `db/install.sql`
   2) seed `db/seed/sales_seed.sql`
   3) smoke `scripts/smoke.sql`
2. Test
   1) jak dev, seed opcjonalnie
3. Prod
   1) bez seeda
   2) import APEX
   3) smoke w trybie read-only

## 10. Ryzyka i decyzje
1. Decyzja v1: whitelist na `AI_V_SALES_*` zamiast dostępu do tabel.
2. Decyzja v1: komentarze kolumn jako główne “źródło semantyki” dla LLM.
3. Ryzyko: LLM będzie próbował używać tabel zamiast widoków, więc guard musi to twardo blokować.
4. Plan v2:
   1) krok “intent” przed SQL (żeby lepiej dobierać widok i filtry)
   2) cache kontekstu metadanych (hash whitelisty)
   3) feedback loop z UI (“popraw”) i dataset do regresji
