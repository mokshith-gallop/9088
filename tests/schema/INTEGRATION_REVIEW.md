# Integration Review Report — NBCS BigQuery Physical Schema DDL

**Date:** 2026-06-27  
**Scope:** 100 tables + 15 views across 3 datasets (nbcs_staging, nbcs_ods, nbcs_dm)  
**Artifacts:** 9 DDL files (`ddl/00-08`), 1 MVS spec (`tests/schema/nbcs_schema_conformance.mvs.yaml`)

---

## Check 1: FK↔PK Type Consistency (AC5)

**45 FK→PK paths verified — 0 type mismatches.**

Checked all FK relationships from `tables.yaml` (fk= tags) and all cross-dataset
join paths from the 15 views. Every FK column type matches its referenced PK column
type after mapping.

Key paths verified:
- Staging→ODS: `stg_crm_program.client_id INT64 ↔ ods_client_acid.client_id INT64`
- ODS→DM: `ods_interaction.agent_id INT64 ↔ dim_agent.agent_id INT64`
- DM fact→dim: `fact_interaction.agent_sk INT64 ↔ dim_agent.agent_sk INT64`
- DM dim→dim: `dim_agent.hire_date_key INT64 ↔ dim_date.date_key INT64`
- Cross-dataset view: `dim_queue.queue_id INT64 ↔ stg_crm_sla_target.queue_id INT64`
- Type-bridged join: `ods_timesheet.work_month STRING ↔ agg_billing_monthly.period_month DATE`
  → bridged by `PARSE_DATE('%Y-%m', work_month)` in `vw_program_margin`

## Check 2: Reserved Word Check (AC2)

**413 unique column names — 0 collisions with BigQuery reserved words.**

Scanned against the full BQ reserved word list (ALL, AND, ARRAY, AS, BETWEEN, BY,
CASE, CREATE, CROSS, FROM, GROUP, HAVING, IN, JOIN, LEFT, LIMIT, MERGE, NOT, NULL,
ON, OR, ORDER, OVER, PARTITION, RANGE, SELECT, SET, STRUCT, TABLE, UNION, WHERE,
WINDOW, WITH, etc.). No column name in the NBCS schema collides.

## Check 3: Epoch/Lie Column Coverage (AC2)

**68 tagged columns — all descriptions present in MVS.**

| Tag | Count | Description | Status |
|-----|-------|-------------|--------|
| `epoch_sec` | 34 | `epoch SECONDS (legacy)` | ✓ 34/34 |
| `epoch_ms` | 28 | `epoch MILLISECONDS (legacy)` | ✓ 28/28 |
| `lie_ms` | 2 | `!! name says seconds, VALUES ARE MILLIS !!` | ✓ 2/2 |
| `ora_str` | 4 | `Oracle string YYYYMMDDHH24MISS (legacy)` | ✓ 4/4 |

LIE columns: `stg_fin_invoice.issued_ts_sec`, `stg_fin_invoice.due_ts_sec`  
Oracle strings: `stg_crm_contract.start_dt`, `.end_dt`, `.signed_dt`, `stg_crm_contract_line.effective_dt`

## Check 4: Partition Matrix Completeness (AC4)

**100/100 tables — all partition/cluster configs match locked performance matrix.**

| Category | Count | Partition | Cluster | Status |
|----------|-------|-----------|---------|--------|
| Sqoop mirrors (normal) | 25 | `load_date` | none | ✓ |
| stg_wfm_schedule | 1 | `load_date` | `[site_code]` | ✓ |
| stg_tel_call | 1 | `load_date` | `[call_id]` | ✓ |
| Delta feeds | 8 | `extract_ts` | none | ✓ |
| File feeds | 10 | `feed_date` | `[client_code]` | ✓ |
| ODS cleanse | 15 | date col | PK | ✓ |
| ODS delta-merge | 8 | none | PK | ✓ |
| ODS SCD-2 | 3 | `eff_from_year` (RANGE) | `[agent_id]` | ✓ |
| ODS ACID | 4 | none | PK | ✓ |
| DM dimensions | 9 | none | SK | ✓ |
| fact_interaction | 1 | `date_key` | `[channel, agent_sk, client_sk]` | ✓ |
| Other facts | 8 | `date_key`/`period_month` | dim key | ✓ |
| Aggregates | 7 | `date_key`/`week_start_key`/`period_month` | grouping dim | ✓ |

## Check 5: View Cross-References (AC7)

**15/15 views — all table references resolve, all dialect translations correct.**

- 0 hardcoded dataset qualifiers (`staging.`, `ods.`, `dm.`) in executable SQL
- 32 table references all resolve to tables defined in DDL files 01-07
- All 10 dialect traps translated:
  - `NDV` → `APPROX_COUNT_DISTINCT` (0 NDV in executable code)
  - `GROUPING__ID` → `GROUPING() * 2 + GROUPING()` (0 GROUPING__ID in executable code)
  - `RLIKE` → `REGEXP_CONTAINS` (0 RLIKE in executable code)
  - `unix_timestamp` → `TIMESTAMP_DIFF` / `UNIX_SECONDS` (0 unix_timestamp in executable code)
  - `from_unixtime` → `TIMESTAMP_MILLIS` (0 from_unixtime in executable code)
  - `date_add` → `TIMESTAMP_ADD` (0 date_add in executable code)
  - `PARSE_DATE` bridge for STRING↔DATE joins
  - Shrinkage simplified: both `sched_date` and `date_key` are DATE

## Check 6: Column Count Verification (AC2)

**916 columns — Hive source, BQ DDL, and MVS spec all match exactly.**

| Source | Columns | Tables |
|--------|---------|--------|
| Hive DDL (02-08) | 916 | 100 |
| BigQuery DDL (01-07) | 916 | 100 |
| MVS spec (tables only) | 916 | 100 |
| MVS spec (+ view columns) | 1,031 | 115 |

---

## Summary

| Check | AC | Result |
|-------|-----|--------|
| FK↔PK type consistency | AC5 | **45/45 pass, 0 fail** |
| Reserved word collisions | AC2 | **413 names, 0 collisions** |
| Epoch/lie/ora_str descriptions | AC2 | **68/68 pass, 0 fail** |
| Partition matrix completeness | AC4 | **100/100 pass, 0 fail** |
| View cross-references | AC7 | **15/15 views, 0 dialect artifacts** |
| Column count parity | AC2 | **916/916/916 match** |

**All cross-checks pass. The DDL files and MVS spec are complete and internally
consistent, ready for harness execution.**
