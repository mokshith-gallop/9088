-- ----------------------------------------------------------------------------
-- 05-ods-delta-scd2.sql
-- BigQuery DDL for ODS: delta-merged entities (8) + SCD-2 histories (3).
-- Translated from hive/ddl/06-ods-delta-scd2.hql.
--
-- Delta-merge tables (8): NO partitioning — per locked performance matrix.
--   Former Hive partition columns (work_month, period_month, event_date,
--   swap_month, event_month, snapshot_date) STAY STRING (not converted to DATE
--   because they are not BQ partition keys on these tables).
--   Clustered by primary key.
--
-- SCD-2 tables (3): RANGE partition on eff_from_year (INT64).
--   PARTITION BY RANGE_BUCKET(eff_from_year, GENERATE_ARRAY(2020, 2030, 1)).
--   Clustered by agent_id.
--
-- Type mapping: BIGINT→INT64, INT→INT64, TIMESTAMP→TIMESTAMP,
--               STRING→STRING, BOOLEAN→BOOL, DECIMAL(p,s)→NUMERIC(p,s).
-- Hive STORED AS PARQUET, TBLPROPERTIES → stripped.
-- ----------------------------------------------------------------------------

-- ===== Delta-merge tables (8) — no partitioning =============================

CREATE TABLE IF NOT EXISTS ods_timesheet (
  timesheet_id        INT64,
  agent_id            INT64,
  work_date           STRING,
  program_id          INT64,
  billable_minutes    INT64,
  nonbillable_minutes INT64,
  approved_flag       BOOL,
  last_change_ts      TIMESTAMP,
  work_month          STRING
)
CLUSTER BY timesheet_id;

CREATE TABLE IF NOT EXISTS ods_payroll_adjustment (
  adjustment_id   INT64,
  agent_id        INT64,
  adj_type        STRING,
  amount          NUMERIC(12,2),
  last_change_ts  TIMESTAMP,
  period_month    STRING
)
CLUSTER BY adjustment_id;

CREATE TABLE IF NOT EXISTS ods_sla_credit (
  sla_credit_id   INT64,
  program_id      INT64,
  sla_target_id   INT64,
  credit_amount   NUMERIC(12,2),
  reason          STRING,
  last_change_ts  TIMESTAMP,
  period_month    STRING
)
CLUSTER BY sla_credit_id;

CREATE TABLE IF NOT EXISTS ods_callback_request (
  callback_id     INT64,
  call_id         INT64,
  queue_id        INT64,
  requested_ts    TIMESTAMP,
  scheduled_ts    TIMESTAMP,
  completed_flag  BOOL,
  last_change_ts  TIMESTAMP,
  event_date      STRING
)
CLUSTER BY callback_id;

CREATE TABLE IF NOT EXISTS ods_shift_swap (
  swap_id              INT64,
  requesting_agent_id  INT64,
  accepting_agent_id   INT64,
  schedule_id          INT64,
  swap_date            STRING,
  status               STRING,
  last_change_ts       TIMESTAMP,
  swap_month           STRING
)
CLUSTER BY swap_id;

CREATE TABLE IF NOT EXISTS ods_ticket_worklog (
  worklog_id      INT64,
  ticket_id       INT64,
  agent_id        INT64,
  minutes_logged  INT64,
  log_ts          TIMESTAMP,
  note            STRING,
  last_change_ts  TIMESTAMP,
  event_date      STRING
)
CLUSTER BY worklog_id;

CREATE TABLE IF NOT EXISTS ods_attrition_event (
  attrition_event_id  INT64,
  agent_id            INT64,
  notice_ts           TIMESTAMP,
  last_day            STRING,
  attrition_type      STRING,
  reason_code         STRING,
  regrettable_flag    BOOL,
  last_change_ts      TIMESTAMP,
  event_month         STRING
)
CLUSTER BY attrition_event_id;

CREATE TABLE IF NOT EXISTS ods_rate_card (
  rate_card_id    INT64,
  program_id      INT64,
  service_code    STRING,
  rate            NUMERIC(12,4),
  currency        STRING,
  effective_ts    TIMESTAMP,
  expiry_ts       TIMESTAMP,
  last_change_ts  TIMESTAMP,
  snapshot_date   STRING
)
CLUSTER BY rate_card_id;

-- ===== SCD-2 history tables (3) — RANGE partition on eff_from_year ==========

CREATE TABLE IF NOT EXISTS ods_agent_scd2 (
  agent_history_id  STRING,
  agent_id          INT64,
  employee_no       STRING,
  org_unit_id       INT64,
  job_grade         STRING,
  employment_type   STRING,
  status            STRING,
  eff_from_ts       TIMESTAMP,
  eff_to_ts         TIMESTAMP,
  is_current        BOOL,
  eff_from_year     INT64
)
PARTITION BY RANGE_BUCKET(eff_from_year, GENERATE_ARRAY(2020, 2030, 1))
CLUSTER BY agent_id;

CREATE TABLE IF NOT EXISTS ods_agent_skill_scd2 (
  agent_skill_history_id  STRING,
  agent_id                INT64,
  skill_id                INT64,
  skill_code              STRING,
  proficiency             INT64,
  certified               BOOL,
  eff_from_ts             TIMESTAMP,
  eff_to_ts               TIMESTAMP,
  is_current              BOOL,
  eff_from_year           INT64
)
PARTITION BY RANGE_BUCKET(eff_from_year, GENERATE_ARRAY(2020, 2030, 1))
CLUSTER BY agent_id;

CREATE TABLE IF NOT EXISTS ods_agent_assignment_scd2 (
  assignment_history_id  STRING,
  agent_id               INT64,
  program_id             INT64,
  queue_id               INT64,
  role_on_program        STRING,
  eff_from_ts            TIMESTAMP,
  eff_to_ts              TIMESTAMP,
  is_current             BOOL,
  eff_from_year          INT64
)
PARTITION BY RANGE_BUCKET(eff_from_year, GENERATE_ARRAY(2020, 2030, 1))
CLUSTER BY agent_id;
