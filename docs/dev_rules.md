# dev_rules

**Cel**

Ten projekt ma być łatwy w utrzymaniu i powtarzalny między dev/test/prod. Repo jest źródłem prawdy. Stan środowiska bez commita nie istnieje.

**Struktura repo**
1. db/
   1) install.sql: instaluje wszystko (tabele, pakiety, role, widoki, seed opcjonalnie)
   2) seed/: dane testowe i demo (np. seed/sales_seed.sql)
   3) ddl/: czyste DDL (tabele, widoki, constrainty)
   4) plsql/: paczki, typy, procedury
2. apex/
   Eksport aplikacji APEX (najlepiej split), plus ewentualnie pliki statyczne.
3. docs/
   1) arch.md: architektura i flow NL→SQL
   2) dev_rules.md: ten dokument
4. scripts/
   Smoke testy i helpery (np. sanity selecty, weryfikacja komentarzy).
5. ci/
   Skrypty pod pipeline (lint, export, checks).

**Zasady zmian**
1. Każda zmiana w DB musi mieć skrypt w repo.
2. Seed to tylko demo/test. Produkcyjnie seed nie idzie automatem.
3. Nie commitujemy sekretów. Klucze i endpointy trzymamy w zmiennych CI albo w credentialach po stronie APEX/DB.
4. Nazwy obiektów trzymamy konsekwentnie:
   1) tabele domeny: SALES_*
   2) słowniki: SALES_LU_*
   3) widoki encji: V_SALES_*
   4) widoki raportowe (whitelist NL→SQL): AI_V_SALES_*

**Styl SQL/PLSQL**
1. Małe paczki i procedury, bez „kombajnów”.
2. Jedno miejsce na obsługę błędów (w paczkach) i sensowne komunikaty do APEX.
3. W widokach AI_V_* tylko pola bezpieczne, do raportowania i NL→SQL.
4. Komentarze na tabelach i kolumnach są obowiązkowe dla AI_V_* i V_*.

**Instalacja lokalna (dev)**
Założenie: masz dostęp do schematu w Oracle (19c) i narzędzie SQLcl albo SQL Developer.
1. Odpal instalację:
   1) uruchom db/install.sql
   2) instalator ma tworzyć obiekty i opcjonalnie odpalić seed
2. Seed danych demo:
   1) uruchom db/seed/sales_seed.sql (jeśli install nie robi tego sam)
3. Smoke test:
   1) uruchom scripts/smoke.sql
   2) oczekuj, że AI_V_* zwróci dane i ma komentarze

**Export APEX**
Cel: aplikacja w repo, nie tylko w środowisku.
1. Narzędzie: SQLcl (lokalnie).
2. Export:
   1) apex export z opcją split
   2) wynik zapisujesz w apex/
   3) commit do repo
3. Import:
   1) import robisz na docelowym środowisku z plików w apex/
   2) po imporcie robisz szybki smoke (logowanie, 1 raport, 1 NL→SQL call)

**Pipeline CI**
1. Lint/format-check:
   1) sprawdza format SQL/PLSQL
   2) failuje jeśli są różnice albo błędy składni w prostych checkach
2. Secrets check:
   1) skan na przypadkowe tokeny i hasła
3. Apex export (manual):
   1) job manualny, żeby odświeżyć eksport z wybranego środowiska i wrzucić artefakt

**Checklist przed mergem**
1. Skrypt instalacji przechodzi od zera na czystym schemacie.
2. AI_V_* ma tylko bezpieczne kolumny i ma komentarze.
3. Smoke test przechodzi.
4. Brak sekretów w repo.
