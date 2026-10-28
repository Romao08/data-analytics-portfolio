"""
Bloom Product Data Challenge - Data Cleaning & Validation

This script performs data quality checks across the four provided datasets:
members, sessions, engagement_events, and outcomes.

It checks schema, missingness, duplicate keys, date parsing, join integrity,
invalid values, structural missingness, and validates key derived metrics such
as weekly_adherence_pct.

Outputs:
- outputs/data_quality_flags.csv
"""

import pandas as pd
import numpy as np
from pathlib import Path


# ======================================================
# CONFIG
# ======================================================

DATA_DIR = Path("data")
OUTPUT_DIR = Path("outputs")
OUTPUT_DIR.mkdir(exist_ok=True)

flags = []


def add_flag(table, issue, count, severity, recommendation):
    flags.append({
        "table": table,
        "issue": issue,
        "count": int(count),
        "severity": severity,
        "recommendation": recommendation
    })


def print_section(title):
    print("\n" + "=" * 90)
    print(title)
    print("=" * 90)


def require_columns(df, table_name, columns):
    missing = [col for col in columns if col not in df.columns]
    if missing:
        add_flag(
            table_name,
            f"Missing required columns: {missing}",
            len(missing),
            "critical",
            "Check source file schema before running analysis."
        )
        return False
    return True


def is_true(series):
    """
    Handles boolean columns that may be stored as True/False, 1/0, or strings.
    """
    return series.astype(str).str.lower().isin(["true", "1", "yes"])


# ======================================================
# LOAD DATASETS
# ======================================================

print_section("LOAD DATASETS")

members = pd.read_csv(DATA_DIR / "members.csv")
sessions = pd.read_csv(DATA_DIR / "sessions.csv")
engagement = pd.read_csv(DATA_DIR / "engagement_events.csv")
outcomes = pd.read_csv(DATA_DIR / "outcomes.csv")

datasets = {
    "members": members,
    "sessions": sessions,
    "engagement_events": engagement,
    "outcomes": outcomes
}

for name, df in datasets.items():
    print(f"{name}: {df.shape[0]} rows, {df.shape[1]} columns")


# ======================================================
# BASIC DATA QUALITY CHECKS
# ======================================================

print_section("BASIC DATA QUALITY CHECKS")

for name, df in datasets.items():
    print(f"\nTABLE: {name}")
    print("-" * 90)

    print("Shape:", df.shape)

    print("\nData types:")
    print(df.dtypes)

    print("\nMissing values:")
    missing = df.isnull().sum()
    print(missing[missing > 0])

    print("\nMissing %:")
    missing_pct = (df.isnull().mean() * 100).round(2)
    print(missing_pct[missing_pct > 0])

    duplicate_rows = df.duplicated().sum()
    print("\nDuplicated rows:", duplicate_rows)

    print("\nUnique values per column:")
    print(df.nunique().sort_values(ascending=False))

    for col in df.columns:
        null_count = df[col].isnull().sum()
        if null_count > 0:
            add_flag(
                table=name,
                issue=f"Missing values in {col}",
                count=null_count,
                severity="check",
                recommendation="Investigate whether missing values are structural before filling."
            )

    if duplicate_rows > 0:
        add_flag(
            table=name,
            issue="Duplicated rows",
            count=duplicate_rows,
            severity="warning",
            recommendation="Review duplicated rows before analysis."
        )


# ======================================================
# PRIMARY KEY / UNIQUE KEY CHECKS
# ======================================================

print_section("PRIMARY KEY / UNIQUE KEY CHECKS")

key_checks = [
    ("members", members, ["member_id"]),
    ("sessions", sessions, ["session_id"]),
    ("engagement_events", engagement, ["event_id"]),
    ("outcomes", outcomes, ["member_id", "week_number"])
]

for table_name, df, key_cols in key_checks:
    if require_columns(df, table_name, key_cols):
        duplicated_keys = df.duplicated(subset=key_cols).sum()

        print(f"{table_name} key {key_cols}: {duplicated_keys} duplicated keys")

        if duplicated_keys > 0:
            add_flag(
                table=table_name,
                issue=f"Duplicated key: {key_cols}",
                count=duplicated_keys,
                severity="critical",
                recommendation="Duplicated keys can break joins and inflate metrics. Fix before analysis."
            )


# ======================================================
# DATE PARSING CHECKS
# ======================================================

print_section("DATE PARSING CHECKS")

date_checks = [
    ("members", members, "signup_date"),
    ("sessions", sessions, "session_date"),
    ("engagement_events", engagement, "event_date")
]

for table_name, df, date_col in date_checks:
    if date_col in df.columns:
        original_nulls = df[date_col].isnull().sum()
        df[date_col] = pd.to_datetime(df[date_col], errors="coerce")
        parsed_nulls = df[date_col].isnull().sum()
        new_parse_failures = parsed_nulls - original_nulls

        print(f"{table_name}.{date_col}: {new_parse_failures} parsing failures")

        if new_parse_failures > 0:
            add_flag(
                table=table_name,
                issue=f"Date parsing failures in {date_col}",
                count=new_parse_failures,
                severity="critical",
                recommendation="Fix invalid date formats before time-series analysis."
            )


# ======================================================
# FOREIGN KEY / JOIN INTEGRITY CHECKS
# ======================================================

print_section("JOIN INTEGRITY CHECKS")

if require_columns(members, "members", ["member_id"]):
    member_ids = set(members["member_id"])

    for table_name, df in [
        ("sessions", sessions),
        ("engagement_events", engagement),
        ("outcomes", outcomes)
    ]:
        if "member_id" in df.columns:
            child_member_ids = set(df["member_id"])
            missing_members = child_member_ids - member_ids

            print(f"{table_name}: {len(missing_members)} member_ids not found in members")

            if len(missing_members) > 0:
                add_flag(
                    table=table_name,
                    issue="member_id not found in members",
                    count=len(missing_members),
                    severity="critical",
                    recommendation="Rows with unknown members can break member-level analysis."
                )


# ======================================================
# RANGE / INVALID VALUE CHECKS
# ======================================================

print_section("RANGE / INVALID VALUE CHECKS")

# Members
if "age" in members.columns:
    invalid_age = members[(members["age"] < 0) | (members["age"] > 120)]
    print("Invalid ages:", len(invalid_age))

    if len(invalid_age) > 0:
        add_flag(
            "members",
            "Invalid age values",
            len(invalid_age),
            "critical",
            "Age should be within a realistic range."
        )

if "baseline_pain_score" in members.columns:
    invalid_baseline_pain = members[
        (members["baseline_pain_score"] < 0) |
        (members["baseline_pain_score"] > 10)
    ]
    print("Invalid baseline pain scores:", len(invalid_baseline_pain))

    if len(invalid_baseline_pain) > 0:
        add_flag(
            "members",
            "Invalid baseline_pain_score values",
            len(invalid_baseline_pain),
            "critical",
            "Pain scores should be between 0 and 10."
        )

if "plan_length_weeks" in members.columns:
    print("\nPlan length values:")
    print(members["plan_length_weeks"].value_counts().sort_index())

if "condition" in members.columns:
    print("\nCondition values:")
    print(members["condition"].value_counts())

if "referral_source" in members.columns:
    print("\nReferral source values:")
    print(members["referral_source"].value_counts())


# Outcomes
if "weekly_adherence_pct" in outcomes.columns:
    invalid_adherence = outcomes[
        (outcomes["weekly_adherence_pct"] < 0) |
        (outcomes["weekly_adherence_pct"] > 100)
    ]
    print("\nInvalid weekly_adherence_pct:", len(invalid_adherence))

    if len(invalid_adherence) > 0:
        add_flag(
            "outcomes",
            "Invalid weekly_adherence_pct values",
            len(invalid_adherence),
            "critical",
            "Adherence should be between 0 and 100."
        )

    print("\nAdherence values:")
    print(outcomes["weekly_adherence_pct"].value_counts().sort_index())

if "satisfaction_proxy" in outcomes.columns:
    invalid_satisfaction = outcomes[
        outcomes["satisfaction_proxy"].notnull() &
        (
            (outcomes["satisfaction_proxy"] < 1) |
            (outcomes["satisfaction_proxy"] > 5)
        )
    ]
    print("\nInvalid satisfaction_proxy:", len(invalid_satisfaction))

    if len(invalid_satisfaction) > 0:
        add_flag(
            "outcomes",
            "Invalid satisfaction_proxy values",
            len(invalid_satisfaction),
            "critical",
            "Satisfaction should normally be between 1 and 5."
        )

if "avg_post_session_pain" in outcomes.columns:
    invalid_outcome_pain = outcomes[
        outcomes["avg_post_session_pain"].notnull() &
        (
            (outcomes["avg_post_session_pain"] < 0) |
            (outcomes["avg_post_session_pain"] > 10)
        )
    ]
    print("Invalid avg_post_session_pain:", len(invalid_outcome_pain))

    if len(invalid_outcome_pain) > 0:
        add_flag(
            "outcomes",
            "Invalid avg_post_session_pain values",
            len(invalid_outcome_pain),
            "critical",
            "Pain values should be between 0 and 10."
        )


# Sessions
if "duration_min" in sessions.columns:
    negative_duration = sessions[sessions["duration_min"] < 0]
    print("\nNegative session duration:", len(negative_duration))

    if len(negative_duration) > 0:
        add_flag(
            "sessions",
            "Negative duration_min",
            len(negative_duration),
            "critical",
            "Negative durations are invalid. Exclude from averages or set to NULL."
        )

for pain_col in ["pre_session_pain", "post_session_pain"]:
    if pain_col in sessions.columns:
        invalid_pain = sessions[
            sessions[pain_col].notnull() &
            (
                (sessions[pain_col] < 0) |
                (sessions[pain_col] > 10)
            )
        ]
        print(f"Invalid {pain_col}:", len(invalid_pain))

        if len(invalid_pain) > 0:
            add_flag(
                "sessions",
                f"Invalid {pain_col} values",
                len(invalid_pain),
                "critical",
                "Pain values should be between 0 and 10."
            )

if "session_type" in sessions.columns:
    print("\nSession types:")
    print(sessions["session_type"].value_counts())


# Engagement events
if "event_type" in engagement.columns:
    print("\nEvent types:")
    print(engagement["event_type"].value_counts())


# ======================================================
# STRUCTURAL MISSINGNESS CHECKS
# ======================================================

print_section("STRUCTURAL MISSINGNESS CHECKS")

if {"avg_post_session_pain", "weekly_adherence_pct"}.issubset(outcomes.columns):
    missing_outcome_pain = outcomes[outcomes["avg_post_session_pain"].isnull()]

    print("\nOutcomes: adherence distribution when avg_post_session_pain is missing")
    print(missing_outcome_pain["weekly_adherence_pct"].value_counts().sort_index())

    if len(missing_outcome_pain) > 0:
        if (missing_outcome_pain["weekly_adherence_pct"] == 0).all():
            add_flag(
                "outcomes",
                "avg_post_session_pain missing only when adherence is 0",
                len(missing_outcome_pain),
                "info",
                "Structural missingness. Do not fill with mean. Keep NULL or add a has_pain_score flag."
            )
        else:
            add_flag(
                "outcomes",
                "avg_post_session_pain missing with non-zero adherence",
                len(missing_outcome_pain),
                "warning",
                "Investigate because pain missingness may affect outcome analysis."
            )

if {"session_type", "planned", "completed", "pre_session_pain", "post_session_pain"}.issubset(sessions.columns):
    print("\nSessions: pain missing rate by session_type / planned / completed")

    pain_missing_by_type = (
        sessions
        .groupby(["session_type", "planned", "completed"])
        .agg(
            rows=("session_id", "count"),
            pre_pain_missing_pct=("pre_session_pain", lambda x: round(x.isnull().mean() * 100, 2)),
            post_pain_missing_pct=("post_session_pain", lambda x: round(x.isnull().mean() * 100, 2))
        )
        .reset_index()
    )

    print(pain_missing_by_type)


# ======================================================
# VALIDATE OUTCOMES AGAINST SESSIONS
# ======================================================

print_section("VALIDATE OUTCOMES AGAINST SESSIONS")

required_for_adherence = {
    "member_id", "week_number", "session_id", "planned", "completed", "session_type"
}

if required_for_adherence.issubset(sessions.columns) and {"member_id", "week_number", "weekly_adherence_pct"}.issubset(outcomes.columns):

    planned_exercise_sessions = sessions[
        (sessions["session_type"] == "exercise") &
        (is_true(sessions["planned"]))
    ].copy()

    sessions_weekly = (
        planned_exercise_sessions
        .groupby(["member_id", "week_number"])
        .agg(
            planned_exercise_sessions=("session_id", "count"),
            completed_planned_exercise_sessions=("completed", lambda x: is_true(x).sum())
        )
        .reset_index()
    )

    sessions_weekly["calculated_adherence_pct"] = (
        100.0 *
        sessions_weekly["completed_planned_exercise_sessions"] /
        sessions_weekly["planned_exercise_sessions"]
    ).round(1)

    adherence_check = outcomes.merge(
        sessions_weekly,
        on=["member_id", "week_number"],
        how="left"
    )

    adherence_check["planned_exercise_sessions"] = adherence_check["planned_exercise_sessions"].fillna(0)
    adherence_check["completed_planned_exercise_sessions"] = adherence_check["completed_planned_exercise_sessions"].fillna(0)
    adherence_check["calculated_adherence_pct"] = adherence_check["calculated_adherence_pct"].fillna(0)

    adherence_check["adherence_diff"] = (
        adherence_check["weekly_adherence_pct"] -
        adherence_check["calculated_adherence_pct"]
    ).abs()

    adherence_mismatches = adherence_check[adherence_check["adherence_diff"] > 0.2]

    print("Adherence mismatches between outcomes and planned exercise sessions:", len(adherence_mismatches))

    if len(adherence_mismatches) > 0:
        print(adherence_mismatches.head(20))

        add_flag(
            "outcomes/sessions",
            "weekly_adherence_pct does not match calculated planned exercise adherence",
            len(adherence_mismatches),
            "warning",
            "Validate whether adherence uses a different session denominator or rounding rule."
        )

    adherence_check.to_csv(OUTPUT_DIR / "adherence_validation.csv", index=False)
    print("Saved: outputs/adherence_validation.csv")


# Validate avg_post_session_pain from completed exercise sessions
required_for_pain = {
    "member_id", "week_number", "session_type", "completed", "post_session_pain"
}

if required_for_pain.issubset(sessions.columns) and {"member_id", "week_number", "avg_post_session_pain"}.issubset(outcomes.columns):

    session_pain_weekly = (
        sessions[
            (sessions["session_type"] == "exercise") &
            (is_true(sessions["completed"])) &
            (sessions["post_session_pain"].notnull())
        ]
        .groupby(["member_id", "week_number"])
        .agg(
            calculated_avg_post_session_pain=("post_session_pain", "mean")
        )
        .reset_index()
    )

    pain_check = outcomes.merge(
        session_pain_weekly,
        on=["member_id", "week_number"],
        how="left"
    )

    pain_check["pain_diff"] = (
        pain_check["avg_post_session_pain"] -
        pain_check["calculated_avg_post_session_pain"]
    ).abs()

    pain_mismatches = pain_check[
        pain_check["avg_post_session_pain"].notnull() &
        pain_check["calculated_avg_post_session_pain"].notnull() &
        (pain_check["pain_diff"] > 0.05)
    ]

    print("Avg post-session pain mismatches:", len(pain_mismatches))

    if len(pain_mismatches) > 0:
        print(pain_mismatches.head(20))

        add_flag(
            "outcomes/sessions",
            "avg_post_session_pain does not match completed exercise session average",
            len(pain_mismatches),
            "warning",
            "Validate how avg_post_session_pain is calculated."
        )

    pain_check.to_csv(OUTPUT_DIR / "pain_validation.csv", index=False)
    print("Saved: outputs/pain_validation.csv")


# ======================================================
# CHECK EVENTS AFTER CHURN
# ======================================================

print_section("CHECK EVENTS AFTER CHURN")

if {"member_id", "week_number", "churned_this_week"}.issubset(outcomes.columns) and {"member_id", "week_number", "event_id"}.issubset(engagement.columns):

    churns = (
        outcomes[is_true(outcomes["churned_this_week"])]
        [["member_id", "week_number"]]
        .rename(columns={"week_number": "churn_week"})
    )

    events_after_churn = churns.merge(
        engagement[["member_id", "week_number", "event_id"]],
        on="member_id",
        how="left"
    )

    events_after_churn = events_after_churn[
        events_after_churn["week_number"] > events_after_churn["churn_week"]
    ]

    print("Engagement events after churn:", len(events_after_churn))

    if len(events_after_churn) > 0:
        add_flag(
            "engagement_events/outcomes",
            "Engagement events found after churned_this_week",
            len(events_after_churn),
            "warning",
            "Clarify operational definition of churned_this_week."
        )


# ======================================================
# CHECK WEEKS BEYOND PLAN LENGTH
# ======================================================

print_section("CHECK WEEKS BEYOND PLAN LENGTH")

if {"member_id", "plan_length_weeks"}.issubset(members.columns):
    member_plan = members[["member_id", "plan_length_weeks"]]

    for table_name, df in [
        ("outcomes", outcomes),
        ("sessions", sessions),
        ("engagement_events", engagement)
    ]:
        if {"member_id", "week_number"}.issubset(df.columns):
            tmp = df.merge(member_plan, on="member_id", how="left")
            beyond_plan = tmp[tmp["week_number"] > tmp["plan_length_weeks"]]

            print(f"{table_name}: rows beyond plan length = {len(beyond_plan)}")

            if len(beyond_plan) > 0:
                add_flag(
                    table_name,
                    "Rows beyond member plan length",
                    len(beyond_plan),
                    "warning",
                    "May represent data issue or post-plan activity. Avoid treating all late activity as churn."
                )


# ======================================================
# SAVE DATA QUALITY REPORT
# ======================================================

print_section("SAVE DATA QUALITY REPORT")

flags_df = pd.DataFrame(flags)

if len(flags_df) > 0:
    print(flags_df)
    flags_df.to_csv(OUTPUT_DIR / "data_quality_flags.csv", index=False)
    print("\nSaved: outputs/data_quality_flags.csv")
else:
    print("No flags found.")

print("\nData cleaning and validation complete.")