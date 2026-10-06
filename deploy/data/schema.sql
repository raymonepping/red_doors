-- deploy/data/schema.sql — Red Doors database (prompt 05). Idempotent; run as
-- the postgres superuser by scripts/data.sh with -v vault_admin_password=…
\set ON_ERROR_STOP on

-- ── Door 4: the payroll table ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS payroll (
  employee_id         integer PRIMARY KEY,
  name                text    NOT NULL,
  department          text    NOT NULL,
  monthly_salary_eur  numeric(10,2) NOT NULL,
  iban_masked         text    NOT NULL
);

-- 20 generated (fictional) employees — only when the table is empty.
INSERT INTO payroll (employee_id, name, department, monthly_salary_eur, iban_masked)
SELECT 1000 + g,
       (ARRAY['Noor','Lars','Ines','Tomas','Mira','Jonas','Sofia','Emil','Lena','Pieter','Yara','Hugo','Elif','Sven','Amara','Bram','Nadia','Oscar','Rosa','Kai'])[g] || ' ' ||
       (ARRAY['de Vries','Jensen','Moreau','Novak','Kowalski','Bauer','Rossi','Lindgren','Dubois','Janssen','Haddad','Costa','Yilmaz','Berg','Mensah','Visser','Petrov','Andersen','Silva','Tanaka'])[1 + (g * 7) % 20],
       (ARRAY['Finance','Engineering','Legal','Operations','Sales'])[1 + g % 5],
       round((3200 + (g * 523) % 4800)::numeric, 2),
       'NL** **** **** ' || lpad(((g * 7919) % 10000)::text, 4, '0')
FROM generate_series(1, 20) AS g
WHERE NOT EXISTS (SELECT 1 FROM payroll);

-- ── Door 6: ciphertext only (plaintext is never stored) ──────────────────
CREATE TABLE IF NOT EXISTS merger_docs (
  id          serial PRIMARY KEY,
  title       text NOT NULL,
  ciphertext  text NOT NULL CHECK (ciphertext LIKE 'vault:v%'),
  key_version integer NOT NULL DEFAULT 1,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- ── The API's own schema (prompt 07 grants it via a Vault role) ──────────
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'api_owner') THEN
    CREATE ROLE api_owner NOLOGIN;
  END IF;
END $$;
CREATE SCHEMA IF NOT EXISTS api AUTHORIZATION api_owner;
GRANT SELECT ON merger_docs TO api_owner;

-- ── vault_admin: the only role Vault uses; not a superuser ────────────────
-- CREATEROLE to mint door-4 users; SELECT on payroll WITH GRANT OPTION so it
-- can pass exactly that on; pg_signal_backend to end sessions on revocation;
-- api_owner WITH ADMIN OPTION for prompt 07. Its password is set here once,
-- then rotated by Vault (database/rotate-root) — no human knows it after.
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'vault_admin') THEN
    CREATE ROLE vault_admin LOGIN CREATEROLE;
  END IF;
END $$;
GRANT SELECT ON payroll TO vault_admin WITH GRANT OPTION;
GRANT pg_signal_backend TO vault_admin;
GRANT api_owner TO vault_admin WITH ADMIN OPTION;
GRANT CONNECT ON DATABASE reddoors TO vault_admin;
