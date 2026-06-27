# Implementation Approach

## Implementation Approach: Manual Hive→BigQuery DDL Translation

### Methodology
Manually translate each of the 8 Hive DDL files (02–09) to BigQuery SQL, producing 100 `CREATE TABLE` + 15 `CREATE VIEW` statements. The `manifests/tables.yaml` manifest serves as cross-reference for column tags (epoch encoding, FK paths, complex types) and the Hive DDL files (`hive/ddl/02-09`) serve as the structural source of truth.

### Output File Structure
```
/workspace/project/ddl/
├── 00-create-datasets.sql          -- CREATE SCHEMA IF NOT EXISTS for nbcs_staging, nbcs_ods, nbcs_dm
├── 01-staging-sqoop-mirrors.sql    -- 27 tables (from hive/ddl/02)
├── 02-staging-delta-feeds.sql      -- 8 tables (from hive/ddl/03)
├── 03-staging-file-feeds.sql       -- 10 tables (from hive/ddl/04)
├── 04-ods-cleanse.sql              -- 15 tables (from hive/ddl/05)
├── 05-ods-delta-scd2.sql           -- 8 delta-merge + 3 SCD-2 = 11 tables (from hive/ddl/06)
├── 06-ods-acid.sql                 -- 4 tables (from hive/ddl/07)
├── 07-dm-tables.sql                -- 25 tables: 9 dims + 9 facts + 7 aggs (from hive/ddl/08)
└── 08-dm-views.sql                 -- 15 views (from hive/ddl/09)
```

Files numbered for execution order (datasets first, then staging→ODS→DM, views last after all base tables exist). Each file is self-contained BigQuery Standard SQL.

### Systematic Type Mapping Rules

| Hive Type | BigQuery Type | Notes |
|---|---|---|
| `BIGINT` | `INT64` | |
| `INT` / `SMALLINT` | `INT64` | BQ only has INT64 |
| `STRING` | `STRING` | |
| `BOOLEAN` | `BOOL` | |
| `DOUBLE` | `FLOAT64` | |
| `TIMESTAMP` | `TIMESTAMP` | UTC always |
| `DATE` | `DATE` | |
| `DECIMAL(p,s)` | `NUMERIC` | All source precisions ≤ 14, well within NUMERIC's 29-digit limit |

### Complex Type Mapping (4 columns)

| Source Column | Hive Type | BigQuery Type |
|---|---|---|
| `stg_file_qa_forms.sections` | `ARRAY<STRUCT<section_code:STRING, max_points:INT, scored_points:INT>>` | `ARRAY<STRUCT<section_code STRING, max_points INT64, scored_points INT64>>` — INT→INT64 recursively inside STRUCT |
| `stg_file_chat_transcripts.messages` | `ARRAY<STRUCT<sender:STRING, ts_ms:BIGINT, text:STRING>>` | `ARRAY<STRUCT<sender STRING, ts_ms INT64, text STRING>>` |
| `stg_file_chat_transcripts.metadata` | `MAP<STRING,STRING>` | `ARRAY<STRUCT<key STRING, value STRING>>` — BQ has no native MAP |
| `stg_file_speech_analytics.keywords` | `ARRAY<STRING>` | `ARRAY<STRING>` — native, no change |

### Partition Column Handling

**Rule: Only columns that serve as active BQ partition keys get the STRING/INT → DATE conversion. Former partition columns on non-partitioned tables stay STRING.**

| Table Category (count) | Partition | Partition Column Conversion | Clustering |
|---|---|---|---|
| **Staging sqoop mirrors** (27) | `PARTITION BY load_date` | `load_date STRING` → `load_date DATE` | None (except stg_tel_call: CLUSTER BY call_id) |
| **stg_wfm_schedule** (1 of 27) | `PARTITION BY load_date` | `load_date STRING` → `load_date DATE` | `CLUSTER BY site_code` (was multi-column Hive partition) |
| **Staging delta feeds** (8) | `PARTITION BY extract_ts` | `extract_ts STRING` → `extract_ts DATE` | None |
| **Staging file feeds** (10) | `PARTITION BY feed_date` | `feed_date STRING` → `feed_date DATE`; `client_code` stays STRING | `CLUSTER BY client_code` |
| **ODS cleanse** (15) | `PARTITION BY <date_col>` | `event_date/snapshot_date/sched_date/call_date STRING` → `DATE` | `CLUSTER BY <primary_key>` |
| **ODS delta-merge** (8) | None | Former partition cols (`work_month`, `period_month`, `event_month`, `swap_month`, `event_date`, `snapshot_date`) stay STRING | `CLUSTER BY <primary_key>` |
| **ODS SCD-2** (3) | `RANGE_BUCKET(eff_from_year, ...)` | `eff_from_year INT` → `eff_from_year INT64` (RANGE partition) | `CLUSTER BY agent_id` |
| **ODS ACID** (4) | None | N/A | `CLUSTER BY <primary_key>` |
| **DM dims** (9) | None | N/A | `CLUSTER BY <surrogate_key>` |
| **fact_interaction** | `PARTITION BY date_key` | `date_key INT` → `date_key DATE` | `CLUSTER BY channel, agent_sk, client_sk` |
| **DM other facts** (8) | `PARTITION BY <date_col>` | `date_key INT` → `DATE`; `period_month STRING` → `DATE` | `CLUSTER BY <most_filtered_dim_key>` |
| **DM aggregates** (7) | `PARTITION BY <date_col>` | `date_key/week_start_key INT` → `DATE`; `period_month STRING` → `DATE` | `CLUSTER BY <grouping_dims>` |

**Note on Hive partition columns → BQ regular columns:** In Hive, partition columns are declared separately in `PARTITIONED BY (...)` and are not in the column list. In BigQuery, they are regular columns declared inline, then referenced in `PARTITION BY`. All former Hive partition columns must be added to the BigQuery column list.

### Column Descriptions

Hive `COMMENT` strings are carried to BigQuery column `OPTIONS(description='...')`:

| Column Pattern | Description Carried |
|---|---|
| `*_ts`, `*_epoch` with tag `epoch_sec` | `'epoch SECONDS (legacy)'` |
| `*_ms` with tag `epoch_ms` | `'epoch MILLISECONDS (legacy)'` |
| `issued_ts_sec`, `due_ts_sec` with tag `lie_ms` | `'!! name says seconds, VALUES ARE MILLIS !!'` |
| `start_dt`, `end_dt`, `signed_dt`, `effective_dt` with tag `ora_str` | `'Oracle string YYYYMMDDHH24MISS (legacy)'` |

### Structural Artifacts Removed

All Hive-specific constructs are dropped:
- `EXTERNAL` keyword → all tables become native BQ managed tables
- `STORED AS PARQUET/ORC/TEXTFILE/SEQUENCEFILE/RCFILE` → removed
- `LOCATION 'hdfs://...'` → removed
- `TBLPROPERTIES ('transactional'='true', ...)` → removed
- `ROW FORMAT DELIMITED/SERDE ...` → removed
- `CLUSTERED BY (...) INTO N BUCKETS` → replaced by `CLUSTER BY` (no bucket count)

### View Translation (15 views — all in `nbcs_dm`)

Each view references tables across all 3 datasets using fully qualified names (`nbcs_staging.table`, `nbcs_ods.table`, `nbcs_dm.table`).

**Dialect trap translations applied:**

| View | Trap | Hive/Impala | BigQuery Translation |
|---|---|---|---|
| `vw_org_hierarchy` | Recursive CTE | `WITH RECURSIVE` | `WITH RECURSIVE` — native BQ support |
| `vw_active_agents_ndv` | NDV | `NDV(col)` | `APPROX_COUNT_DISTINCT(col)` |
| `vw_csat_rollup` | GROUPING__ID | `GROUP BY ... WITH ROLLUP` + `GROUPING__ID` | `GROUP BY ROLLUP(...)` + `GROUPING(col1) * 2 + GROUPING(col2)` to reconstruct the bitmask |
| `vw_call_driver_regex` | RLIKE + regexp | `RLIKE '...'`, `regexp_extract(str, pat, grp)` | `REGEXP_CONTAINS(str, r'...')`, `REGEXP_EXTRACT(str, r'...')` — RE2 syntax |
| `vw_repeat_contact_window` | Epoch arithmetic | `unix_timestamp(ts) - unix_timestamp(lag_ts) <= 259200` | `TIMESTAMP_DIFF(ts, lag_ts, SECOND) <= 259200` |
| `vw_billing_reconciliation` | LIE epoch | `from_unixtime(CAST(x/1000 AS BIGINT))` + `unix_timestamp()` | `TIMESTAMP_MILLIS(issued_ts_sec)` + `UNIX_SECONDS()` — preserve millis semantics |
| `vw_queue_sla_attainment` | Layer-skip | `staging.stg_crm_sla_target` | `nbcs_staging.stg_crm_sla_target` — cross-dataset reference |
| `vw_first_contact_resolution` | Self-join + date_add | `date_add(f.end_ts, 7)` | `TIMESTAMP_ADD(f.end_ts, INTERVAL 7 DAY)` |
| `vw_shrinkage_analysis` | from_unixtime chain | Complex date_key→string→date chain | Simplified: since `date_key` is now `DATE`, use `FORMAT_DATE('%Y-%m-%d', f.date_key)` |
| `vw_program_margin` | Cross-type join | `work_month = period_month` (both STRING) | `PARSE_DATE('%Y-%m', lab.work_month) = b.period_month` — bridge STRING↔DATE |

**Type-bridge pattern:** Views joining DM tables (DATE partition columns) against ODS delta-merge tables (STRING former-partition columns) add explicit `PARSE_DATE('%Y-%m', string_col)` to bridge the type mismatch. Affected: `vw_program_margin` (work_month, period_month).

### DDL Pattern Examples

```sql
-- Staging table: partition column promoted from PARTITIONED BY to inline column
CREATE TABLE IF NOT EXISTS nbcs_staging.stg_crm_client (
  client_id   INT64,
  client_code STRING,
  client_name STRING,
  industry    STRING,
  hq_country  STRING,
  status      STRING,
  created_ts  INT64 OPTIONS(description='epoch SECONDS (legacy)'),
  updated_ts  INT64 OPTIONS(description='epoch SECONDS (legacy)'),
  load_date   DATE
)
PARTITION BY load_date;

-- ACID → native BQ table, clustered by PK
CREATE TABLE IF NOT EXISTS nbcs_ods.ods_client_acid (
  client_id   INT64,
  client_code STRING,
  client_name STRING,
  industry    STRING,
  hq_country  STRING,
  status      STRING,
  created_ts  TIMESTAMP,
  updated_ts  TIMESTAMP
)
CLUSTER BY client_id;

-- Multi-col Hive partition → DATE partition + clustering
CREATE TABLE IF NOT EXISTS nbcs_dm.fact_interaction (
  interaction_id STRING,
  client_sk      INT64,
  program_sk     INT64,
  queue_sk       INT64,
  agent_sk       INT64,
  customer_ref   STRING,
  start_ts       TIMESTAMP,
  end_ts         TIMESTAMP,
  handle_seconds INT64,
  resolved_flag  BOOL,
  source_system  STRING,
  date_key       DATE,
  channel        STRING
)
PARTITION BY date_key
CLUSTER BY channel, agent_sk, client_sk;

-- SCD-2 with RANGE partition
CREATE TABLE IF NOT EXISTS nbcs_ods.ods_agent_scd2 (
  agent_history_id STRING,
  agent_id         INT64,
  employee_no      STRING,
  org_unit_id      INT64,
  job_grade        STRING,
  employment_type  STRING,
  status           STRING,
  eff_from_ts      TIMESTAMP,
  eff_to_ts        TIMESTAMP,
  is_current       BOOL,
  eff_from_year    INT64
)
PARTITION BY RANGE_BUCKET(eff_from_year, GENERATE_ARRAY(2020, 2030, 1))
CLUSTER BY agent_id;
```

### Execution Order

1. `00-create-datasets.sql` — create 3 datasets
2. `01` through `06` — staging and ODS tables (can be parallelized within a layer)
3. `07-dm-tables.sql` — all 25 DM tables
4. `08-dm-views.sql` — all 15 views (must come after ALL base tables across all datasets, since views reference cross-dataset tables)
