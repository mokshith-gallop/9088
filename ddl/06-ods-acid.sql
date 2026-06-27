-- ----------------------------------------------------------------------------
-- 06-ods-acid.sql
-- BigQuery DDL for ODS: Hive ACID transactional tables (4).
-- Translated from hive/ddl/07-ods-acid.hql.
--
-- Hive ACID ORC transactional → native BigQuery managed tables.
-- NO partitioning per locked performance matrix.
-- Hive CLUSTERED BY (col) INTO N BUCKETS → CLUSTER BY col (no bucket count).
-- Hive STORED AS ORC, TBLPROPERTIES (transactional, orc.compress) → stripped.
--
-- Type mapping: BIGINT→INT64, TIMESTAMP→TIMESTAMP, STRING→STRING,
--               DECIMAL(14,2)→NUMERIC(14,2).
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS ods_client_acid (
  client_id    INT64,
  client_code  STRING,
  client_name  STRING,
  industry     STRING,
  hq_country   STRING,
  status       STRING,
  created_ts   TIMESTAMP,
  updated_ts   TIMESTAMP
)
CLUSTER BY client_id;

CREATE TABLE IF NOT EXISTS ods_agent_acid (
  agent_id         INT64,
  employee_no      STRING,
  full_name        STRING,
  email            STRING,
  org_unit_id      INT64,
  job_grade        STRING,
  employment_type  STRING,
  hire_ts          TIMESTAMP,
  term_ts          TIMESTAMP,
  status           STRING
)
CLUSTER BY agent_id;

CREATE TABLE IF NOT EXISTS ods_ticket_acid (
  ticket_id          INT64,
  ticket_no          STRING,
  program_id         INT64,
  category_id        INT64,
  assigned_agent_id  INT64,
  priority           STRING,
  status             STRING,
  created_ts         TIMESTAMP,
  updated_ts         TIMESTAMP,
  resolved_ts        TIMESTAMP
)
CLUSTER BY ticket_id;

CREATE TABLE IF NOT EXISTS ods_invoice_acid (
  invoice_id    INT64,
  invoice_no    STRING,
  client_id     INT64,
  program_id    INT64,
  period_month  STRING,
  issued_ts     TIMESTAMP,
  due_ts        TIMESTAMP,
  currency      STRING,
  total_amount  NUMERIC(14,2),
  status        STRING
)
CLUSTER BY invoice_id;
