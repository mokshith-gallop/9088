-- ----------------------------------------------------------------------------
-- 04-ods-cleanse.sql
-- BigQuery DDL for ODS: cleansed/conformed entities (15 tables).
-- Translated from hive/ddl/05-ods-cleanse.hql.
--
-- Type mapping: BIGINT→INT64, INT→INT64, TIMESTAMP→TIMESTAMP,
--               STRING→STRING, BOOLEAN→BOOL, DECIMAL(p,s)→NUMERIC(p,s).
-- Hive PARTITIONED BY (<col> STRING) → inline <col> DATE + PARTITION BY <col>.
-- Each table clustered by its primary key per the locked performance matrix.
-- Hive STORED AS PARQUET, TBLPROPERTIES → stripped (native BQ managed tables).
-- ----------------------------------------------------------------------------

-- Partition columns in this layer:
--   snapshot_date (5 tables)  → DATE
--   sched_date    (1 table)   → DATE
--   event_date    (8 tables)  → DATE
--   call_date     (1 table)   → DATE

CREATE TABLE IF NOT EXISTS ods_program (
  program_id        INT64,
  client_id         INT64,
  program_code      STRING,
  program_name      STRING,
  line_of_business  STRING,
  channel_mix       STRING,
  site_code         STRING,
  status            STRING,
  go_live_ts        TIMESTAMP,
  updated_ts        TIMESTAMP,
  snapshot_date     DATE
)
PARTITION BY snapshot_date
CLUSTER BY program_id;

CREATE TABLE IF NOT EXISTS ods_contract (
  contract_id    INT64,
  client_id      INT64,
  program_id     INT64,
  contract_no    STRING,
  start_ts       TIMESTAMP,
  end_ts         TIMESTAMP,
  billing_model  STRING,
  currency       STRING,
  signed_ts      TIMESTAMP,
  status         STRING,
  snapshot_date  DATE
)
PARTITION BY snapshot_date
CLUSTER BY contract_id;

CREATE TABLE IF NOT EXISTS ods_contract_line (
  contract_line_id  INT64,
  contract_id       INT64,
  line_no           INT64,
  service_code      STRING,
  uom               STRING,
  unit_rate         NUMERIC(12,4),
  min_commit        NUMERIC(12,2),
  effective_ts      TIMESTAMP,
  snapshot_date     DATE
)
PARTITION BY snapshot_date
CLUSTER BY contract_line_id;

CREATE TABLE IF NOT EXISTS ods_org_unit (
  org_unit_id     INT64,
  parent_unit_id  INT64,
  unit_code       STRING,
  unit_name       STRING,
  unit_type       STRING,
  site_code       STRING,
  cost_center     STRING,
  created_ts      TIMESTAMP,
  snapshot_date   DATE
)
PARTITION BY snapshot_date
CLUSTER BY org_unit_id;

CREATE TABLE IF NOT EXISTS ods_queue (
  queue_id       INT64,
  queue_code     STRING,
  queue_name     STRING,
  program_id     INT64,
  media_type     STRING,
  priority       INT64,
  created_ts     TIMESTAMP,
  snapshot_date  DATE
)
PARTITION BY snapshot_date
CLUSTER BY queue_id;

CREATE TABLE IF NOT EXISTS ods_schedule (
  schedule_id    INT64,
  agent_id       INT64,
  shift_id       INT64,
  shift_code     STRING,
  start_ts       TIMESTAMP,
  end_ts         TIMESTAMP,
  paid_minutes   INT64,
  activity_code  STRING,
  site_code      STRING,
  sched_date     DATE
)
PARTITION BY sched_date
CLUSTER BY schedule_id;

CREATE TABLE IF NOT EXISTS ods_adherence_event (
  adherence_event_id  INT64,
  agent_id            INT64,
  schedule_id         INT64,
  exception_type      STRING,
  start_ts            TIMESTAMP,
  end_ts              TIMESTAMP,
  exception_minutes   INT64,
  approved_flag       BOOL,
  event_date          DATE
)
PARTITION BY event_date
CLUSTER BY adherence_event_id;

CREATE TABLE IF NOT EXISTS ods_call (
  call_id           INT64,
  queue_id          INT64,
  agent_id          INT64,
  program_id        INT64,
  direction         STRING,
  start_ts          TIMESTAMP,
  answer_ts         TIMESTAMP,
  end_ts            TIMESTAMP,
  ring_seconds      INT64,
  talk_seconds      INT64,
  hold_seconds      INT64,
  acw_seconds       INT64,
  abandoned_flag    BOOL,
  disposition_code  STRING,
  recording_id      STRING,
  call_date         DATE
)
PARTITION BY call_date
CLUSTER BY call_id;

CREATE TABLE IF NOT EXISTS ods_ivr_session (
  session_ref     STRING,
  client_code     STRING,
  first_event_ts  TIMESTAMP,
  last_event_ts   TIMESTAMP,
  menu_path_full  STRING,
  hops            INT64,
  contained_flag  BOOL,
  exit_key        STRING,
  event_date      DATE
)
PARTITION BY event_date
CLUSTER BY session_ref;

CREATE TABLE IF NOT EXISTS ods_chat_session (
  chat_ref                STRING,
  client_code             STRING,
  queue_code              STRING,
  agent_email             STRING,
  started_ts              TIMESTAMP,
  ended_ts                TIMESTAMP,
  message_count           INT64,
  agent_message_count     INT64,
  customer_message_count  INT64,
  first_response_seconds  INT64,
  event_date              DATE
)
PARTITION BY event_date
CLUSTER BY chat_ref;

CREATE TABLE IF NOT EXISTS ods_email_interaction (
  email_ref          STRING,
  client_code        STRING,
  mailbox            STRING,
  agent_email        STRING,
  received_ts        TIMESTAMP,
  first_reply_ts     TIMESTAMP,
  resolved_ts        TIMESTAMP,
  reply_sla_minutes  INT64,
  subject_category   STRING,
  event_date         DATE
)
PARTITION BY event_date
CLUSTER BY email_ref;

CREATE TABLE IF NOT EXISTS ods_survey_response (
  survey_id        STRING,
  client_code      STRING,
  interaction_ref  STRING,
  survey_ts        TIMESTAMP,
  csat_score       INT64,
  nps_score        INT64,
  fcr_claimed      BOOL,
  verbatim         STRING,
  event_date       DATE
)
PARTITION BY event_date
CLUSTER BY survey_id;

CREATE TABLE IF NOT EXISTS ods_qa_evaluation (
  qa_form_id       STRING,
  client_code      STRING,
  interaction_ref  STRING,
  evaluator_email  STRING,
  evaluated_ts     TIMESTAMP,
  form_version     STRING,
  section_count    INT64,
  scored_points    INT64,
  max_points       INT64,
  auto_fail        BOOL,
  overall_pct      NUMERIC(5,2),
  event_date       DATE
)
PARTITION BY event_date
CLUSTER BY qa_form_id;

CREATE TABLE IF NOT EXISTS ods_interaction (
  interaction_id  STRING,
  channel         STRING,
  client_code     STRING,
  program_id      INT64,
  queue_id        INT64,
  agent_id        INT64,
  customer_ref    STRING,
  start_ts        TIMESTAMP,
  end_ts          TIMESTAMP,
  handle_seconds  INT64,
  resolved_flag   BOOL,
  source_system   STRING,
  event_date      DATE
)
PARTITION BY event_date
CLUSTER BY interaction_id;

CREATE TABLE IF NOT EXISTS ods_dialer_attempt (
  attempt_id      STRING,
  client_code     STRING,
  campaign_code   STRING,
  agent_id        INT64,
  attempt_ts      TIMESTAMP,
  result_code     STRING,
  connected_flag  BOOL,
  talk_seconds    INT64,
  event_date      DATE
)
PARTITION BY event_date
CLUSTER BY attempt_id;
