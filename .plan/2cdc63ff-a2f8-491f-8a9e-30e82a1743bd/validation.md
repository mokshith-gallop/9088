# Validation

## Validation: MVS Spec + Live Catalog Assertions

### Deliverables
1. **BigQuery DDL files** (9 SQL files in `/workspace/project/ddl/`)
2. **Full MVS YAML spec** (`/workspace/project/tests/schema/nbcs_schema_conformance.mvs.yaml`) covering all 100 tables + 15 views across 3 datasets — consumed by the existing `lib/schema.py` harness

### MVS Spec Structure

Three `schema_conformance` suites, one per dataset:

```yaml
name: nbcs_full_schema_conformance
description: NBCS warehouse — 100 tables + 15 views across 3 datasets

connections:
  target: { engine: bigquery }

suites:
  - pattern: schema_conformance
    id: nbcs-staging-schema
    story_id: 2cdc63ff-a2f8-491f-8a9e-30e82a1743bd
    target_dataset: nbcs_staging
    expect_table_count: 45
    tables:
      # 27 sqoop mirrors + 8 delta feeds + 10 file feeds
      # Each with: table name, expect_object_type, partition_by, cluster_by, columns with types/descriptions
      - table: stg_crm_client
        expect_object_type: TABLE
        partition_by: load_date
        columns:
          - { name: client_id, type: INT64, source_type: BIGINT }
          - { name: client_code, type: STRING }
          # ... all columns including load_date DATE
      # ... 44 more tables

  - pattern: schema_conformance
    id: nbcs-ods-schema
    story_id: 2cdc63ff-a2f8-491f-8a9e-30e82a1743bd
    target_dataset: nbcs_ods
    expect_table_count: 30
    tables:
      # 15 cleanse + 8 delta-merge + 3 SCD-2 + 4 ACID
      # ... 30 table entries

  - pattern: schema_conformance
    id: nbcs-dm-schema
    story_id: 2cdc63ff-a2f8-491f-8a9e-30e82a1743bd
    target_dataset: nbcs_dm
    expect_table_count: 40   # 25 tables + 15 views
    tables:
      # 9 dims + 9 facts + 7 aggs + 15 views
      # Views use expect_object_type: VIEW
      # ... 40 entries
```

### Acceptance Criteria → Harness Check Mapping

| AC | What It Asserts | How the MVS Harness Covers It |
|---|---|---|
| **AC1: Table-count parity** | 45 + 30 + 25 = 100 tables, 0 DDL errors | `expect_table_count` per suite (45, 30, 25). Harness queries `INFORMATION_SCHEMA.TABLES`, compares count, and names any missing tables as HARD FAIL. |
| **AC2: Per-column fidelity** | ~830 columns: name, type, ordinal, nullability, description, no reserved words | Every column declared in the MVS with `name`, `type`, `source_type`, `description`. Harness reads `INFORMATION_SCHEMA.COLUMNS` + `COLUMN_FIELD_PATHS` and asserts each column matches. Complex types checked recursively via `COLUMN_FIELD_PATHS`. DECIMAL columns assert NUMERIC type. Epoch columns assert INT64 type + description text. |
| **AC3: Object-type fidelity** | 100 BASE TABLE + 15 VIEW, no silent type flip | `expect_object_type: TABLE` on all 100 table entries, `expect_object_type: VIEW` on all 15 view entries. Harness reads `table_type` from `INFORMATION_SCHEMA.TABLES`. |
| **AC4: Partition/cluster intent** | Correct partition + cluster config per locked matrix | `partition_by` and `cluster_by` on every table entry. Harness reads `INFORMATION_SCHEMA.TABLE_OPTIONS` for partition config and `INFORMATION_SCHEMA.COLUMNS.clustering_ordinal_position` for clustering. |
| **AC5: FK↔PK type consistency** | FK column type matches PK column type on every join path | Column type assertions across suites — e.g., `stg_crm_program.client_id INT64` matches `ods_client_acid.client_id INT64`. The harness validates each column's type independently; cross-dataset consistency is proven by all columns being correct individually. |
| **AC6: Queryability smoke** | `SELECT * LIMIT 0` succeeds for all 100 tables + 3 tier queries | Harness executes `SELECT * FROM dataset.table LIMIT 0` for every declared table. Three tier queries added as custom checks in the test runner (not in MVS, but in the pytest wrapper). |
| **AC7: View creation** | 15 CREATE VIEW with 0 errors, correct SQL translation | Views declared with `expect_object_type: VIEW` in the nbcs-dm suite. Harness verifies existence and type via `INFORMATION_SCHEMA.TABLES`. View SQL correctness proven by successful CREATE (BQ validates all referenced tables/columns at view creation time). |
| **AC8: Integrity guards** | Catalog read-back succeeds for all 115 objects | The harness's core loop reads `INFORMATION_SCHEMA` for every declared object — a missing or unreadable entry is HARD FAIL. |
| **AC9: No-silent-skip** | Every criterion executed against live catalog | The harness reports `checked X of Y` coverage for each check type. The pytest wrapper asserts 0 skipped criteria. |

### Complex Type Validation Detail

For the 4 complex-type columns, the MVS spec declares the full nested type string so the harness validates sub-fields recursively via `INFORMATION_SCHEMA.COLUMN_FIELD_PATHS`:

```yaml
# stg_file_qa_forms.sections
- name: sections
  type: "ARRAY<STRUCT<section_code STRING, max_points INT64, scored_points INT64>>"

# stg_file_chat_transcripts.messages  
- name: messages
  type: "ARRAY<STRUCT<sender STRING, ts_ms INT64, text STRING>>"

# stg_file_chat_transcripts.metadata (MAP → ARRAY<STRUCT>)
- name: metadata
  type: "ARRAY<STRUCT<key STRING, value STRING>>"

# stg_file_speech_analytics.keywords
- name: keywords
  type: "ARRAY<STRING>"
```

The harness reads `COLUMN_FIELD_PATHS` which returns one row per nested field (e.g., `sections.section_code STRING`, `sections.max_points INT64`), and asserts each sub-field name and type matches the declared nested structure.

### DECIMAL Validation

All ~53 DECIMAL columns are declared as `type: NUMERIC` in the MVS. The harness asserts:
- BigQuery type is `NUMERIC` (not `BIGNUMERIC`, since all source precisions ≤ 14)
- Scale matches via `INFORMATION_SCHEMA.COLUMNS.numeric_scale`
- Precision matches via `INFORMATION_SCHEMA.COLUMNS.numeric_precision`

Examples: `DECIMAL(12,4)` → `NUMERIC` with precision=12, scale=4; `DECIMAL(14,2)` → `NUMERIC` with precision=14, scale=2; `DECIMAL(5,2)` → `NUMERIC` with precision=5, scale=2.

### Epoch Column Description Validation

The MVS spec includes `description` on every epoch-tagged column. The harness reads `INFORMATION_SCHEMA.COLUMN_FIELD_PATHS.description` and asserts the text matches:

```yaml
# Epoch seconds
- { name: created_ts, type: INT64, description: "epoch SECONDS (legacy)" }

# Epoch millis
- { name: created_ms, type: INT64, description: "epoch MILLISECONDS (legacy)" }

# LIE columns
- { name: issued_ts_sec, type: INT64, description: "!! name says seconds, VALUES ARE MILLIS !!" }
```

### Reserved Word Check

The harness validates that no column name in the DDL collides with a BigQuery reserved word. Column names are checked against the BQ reserved word list (`SELECT`, `FROM`, `WHERE`, `GROUP`, `ORDER`, `LIMIT`, `JOIN`, `TABLE`, `CREATE`, `INSERT`, `UPDATE`, `DELETE`, `MERGE`, `PARTITION`, `CLUSTER`, etc.). No source columns in the NBCS schema collide — this is a defensive check.

### Test Execution Workflow

1. Apply DDL files 00–08 to scratch BigQuery datasets (created per test run, torn down after)
2. Run the MVS harness (`lib/schema.py`) against the live catalog
3. Execute queryability smoke tests (SELECT * LIMIT 0 for all 100 tables + 3 tier queries)
4. Assert 0 failures across all checks
5. Report coverage: `checked X/Y columns across 100 tables, 0 mismatches`

### Edge Cases Handled

- **4 Hive ACID tables** → verified as `BASE TABLE` (not external), no `transactional` TBLPROPERTY in BQ
- **45 Hive EXTERNAL tables** → verified as `BASE TABLE` (native managed), no `LOCATION` directive
- **`dim_date.date_key`** is a non-partition INT column (dims have no partitioning) — stays `INT64`, not converted to DATE
- **`dim_program.go_live_date_key`** and `dim_agent.hire_date_key`** — INT FK references to dim_date, stay `INT64`
- **Views referencing 3 datasets** — view creation validates all cross-dataset references resolve correctly at CREATE time
