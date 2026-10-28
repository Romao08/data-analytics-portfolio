/*
Bloom Product Data Challenge - Analysis Queries

Purpose:
These queries support the presentation analysis for the Bloom engagement drop between weeks 2 and 4.

Core definition:
Meaningful exercise engagement = weekly_adherence_pct >= 66.7
This maps to completing at least 2 of 3 prescribed weekly exercise sessions.

Primary metric:
Week 4 Meaningful Exercise Engagement Retention =
% of the initial cohort with weekly_adherence_pct >= 66.7 in week 4.

Notes:
- The primary metric uses the initial cohort as denominator.
- This means members missing by week 4 count as not meaningfully engaged.
- Some diagnostic queries use observed members by week when the goal is to understand behavior among members still present in outcomes.
*/


-- ======================================================
-- 0. Quick table previews
-- ======================================================

SELECT TOP 100 *
FROM members;

SELECT TOP 100 *
FROM sessions;

SELECT TOP 100 *
FROM engagement_events;

SELECT TOP 100 *
FROM outcomes;



-- ======================================================
-- 1. Primary metric: Week 4 meaningful engagement retention
-- ======================================================
-- Calculates the main metric used in the deck:
-- % of initial cohort with weekly_adherence_pct >= 66.7% in week 4.

WITH initial_cohort AS (
    SELECT
        COUNT(DISTINCT member_id) AS initial_members
    FROM members
),

week4_engaged AS (
    SELECT
        COUNT(DISTINCT member_id) AS engaged_week4_members
    FROM outcomes
    WHERE week_number = 4
      AND weekly_adherence_pct >= 66.7
)

SELECT
    i.initial_members,
    w.engaged_week4_members,

    ROUND(
        100.0 * w.engaged_week4_members / i.initial_members,
        2
    ) AS week4_meaningful_engagement_retention_pct

FROM initial_cohort i
CROSS JOIN week4_engaged w;



-- ======================================================
-- 2. Meaningful engagement trend by week, using initial cohort denominator
-- ======================================================
-- Shows how the primary engagement metric evolves from week 1 to week 4.
-- This supports the finding that meaningful engagement falls from 61.9% in week 2 to 47.2% in week 4.

WITH initial_cohort AS (
    SELECT
        COUNT(DISTINCT member_id) AS initial_members
    FROM members
),

weekly_engagement AS (
    SELECT
        week_number,

        COUNT(DISTINCT CASE
            WHEN weekly_adherence_pct >= 66.7
            THEN member_id
        END) AS engaged_members

    FROM outcomes
    WHERE week_number BETWEEN 1 AND 4
    GROUP BY week_number
)

SELECT
    w.week_number,
    w.engaged_members,
    i.initial_members,

    ROUND(
        100.0 * w.engaged_members / i.initial_members,
        2
    ) AS engagement_from_initial_cohort_pct

FROM weekly_engagement w
CROSS JOIN initial_cohort i
ORDER BY w.week_number;



-- ======================================================
-- 3. Average adherence among observed members
-- ======================================================
-- Diagnostic query.
-- Checks whether observed members are doing much worse over time.
-- In the final narrative, average adherence among observed members only declines modestly.

SELECT
    week_number,

    COUNT(DISTINCT member_id) AS observed_members,

    ROUND(
        AVG(weekly_adherence_pct),
        2
    ) AS avg_weekly_adherence_pct

FROM outcomes
WHERE week_number BETWEEN 1 AND 4
GROUP BY week_number
ORDER BY week_number;



-- ======================================================
-- 4. Week 2 adherence bucket vs Week 4 meaningful engagement
-- ======================================================
-- Key insight:
-- Members completing only 1 of 3 sessions in week 2 behave almost like members completing 0 of 3 by week 4.
-- The important threshold is reaching at least 2 of 3 prescribed sessions early.

WITH week2 AS (
    SELECT
        member_id,
        weekly_adherence_pct AS week2_adherence_pct,

        CASE
            WHEN weekly_adherence_pct >= 99.9 THEN '100%'
            WHEN weekly_adherence_pct >= 66.7 THEN '66.7%'
            WHEN weekly_adherence_pct >= 33.3 THEN '33.3%'
            ELSE '0%'
        END AS week2_adherence_bucket,

        CASE
            WHEN weekly_adherence_pct >= 99.9 THEN 4
            WHEN weekly_adherence_pct >= 66.7 THEN 3
            WHEN weekly_adherence_pct >= 33.3 THEN 2
            ELSE 1
        END AS bucket_order

    FROM outcomes
    WHERE week_number = 2
),

week4 AS (
    SELECT
        member_id,

        CASE
            WHEN weekly_adherence_pct >= 66.7 THEN 1
            ELSE 0
        END AS engaged_week4

    FROM outcomes
    WHERE week_number = 4
)

SELECT
    w2.week2_adherence_bucket,

    COUNT(DISTINCT w2.member_id) AS members,

    COUNT(DISTINCT CASE
        WHEN w4.engaged_week4 = 1
        THEN w2.member_id
    END) AS engaged_week4_members,

    ROUND(
        100.0 * COUNT(DISTINCT CASE
            WHEN w4.engaged_week4 = 1
            THEN w2.member_id
        END)
        / COUNT(DISTINCT w2.member_id),
        2
    ) AS week4_meaningful_engagement_pct

FROM week2 w2
LEFT JOIN week4 w4
    ON w2.member_id = w4.member_id

GROUP BY
    w2.week2_adherence_bucket,
    w2.bucket_order

ORDER BY
    w2.bucket_order DESC;



-- ======================================================
-- 5. Product activity diagnostics from engagement_events
-- ======================================================
-- Supports the finding that product activity also declines after week 2:
-- non-passive events/user, app opens/user, push open rate, and missed-session signals.

SELECT
    week_number,

    COUNT(DISTINCT member_id) AS users_with_any_event,

    COUNT(CASE
        WHEN event_type <> 'push_received'
        THEN event_id
    END) AS non_passive_events,

    COUNT(DISTINCT CASE
        WHEN event_type <> 'push_received'
        THEN member_id
    END) AS users_with_non_passive_event,

    ROUND(
        1.0 * COUNT(CASE WHEN event_type <> 'push_received' THEN event_id END)
        / NULLIF(COUNT(DISTINCT CASE WHEN event_type <> 'push_received' THEN member_id END), 0),
        2
    ) AS non_passive_events_per_active_user,

    COUNT(CASE
        WHEN event_type = 'app_open'
        THEN event_id
    END) AS app_open_events,

    COUNT(DISTINCT CASE
        WHEN event_type = 'app_open'
        THEN member_id
    END) AS users_with_app_open,

    ROUND(
        1.0 * COUNT(CASE WHEN event_type = 'app_open' THEN event_id END)
        / NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'app_open' THEN member_id END), 0),
        2
    ) AS app_opens_per_user,

    COUNT(CASE
        WHEN event_type = 'push_received'
        THEN event_id
    END) AS push_received_events,

    COUNT(CASE
        WHEN event_type = 'push_opened'
        THEN event_id
    END) AS push_opened_events,

    ROUND(
        100.0 * COUNT(CASE WHEN event_type = 'push_opened' THEN event_id END)
        / NULLIF(COUNT(CASE WHEN event_type = 'push_received' THEN event_id END), 0),
        2
    ) AS push_open_rate_pct,

    COUNT(CASE
        WHEN event_type = 'missed_session'
        THEN event_id
    END) AS missed_session_events,

    COUNT(DISTINCT CASE
        WHEN event_type = 'missed_session'
        THEN member_id
    END) AS users_with_missed_session,

    ROUND(
        1.0 * COUNT(CASE WHEN event_type = 'missed_session' THEN event_id END)
        / NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'missed_session' THEN member_id END), 0),
        2
    ) AS missed_session_events_per_user

FROM engagement_events
WHERE week_number BETWEEN 1 AND 4
GROUP BY week_number
ORDER BY week_number;



-- ======================================================
-- 6. Push volume vs Week 4 engagement
-- ======================================================
-- Tests whether higher push volume appears associated with lower week 4 engagement.
-- Interpretation used in deck:
-- Push open rate declines, but higher push volume itself was not enough evidence to claim notification fatigue.

WITH push_volume AS (
    SELECT
        m.member_id,

        COUNT(CASE
            WHEN e.event_type = 'push_received'
             AND e.week_number BETWEEN 1 AND 2
            THEN e.event_id
        END) AS pushes_received_w1_w2,

        COUNT(CASE
            WHEN e.event_type = 'push_opened'
             AND e.week_number BETWEEN 1 AND 2
            THEN e.event_id
        END) AS pushes_opened_w1_w2

    FROM members m
    LEFT JOIN engagement_events e
        ON m.member_id = e.member_id

    GROUP BY m.member_id
),

push_buckets AS (
    SELECT
        member_id,
        pushes_received_w1_w2,
        pushes_opened_w1_w2,

        CASE
            WHEN pushes_received_w1_w2 = 0 THEN '0 pushes'
            WHEN pushes_received_w1_w2 BETWEEN 1 AND 5 THEN '1-5 pushes'
            WHEN pushes_received_w1_w2 BETWEEN 6 AND 10 THEN '6-10 pushes'
            WHEN pushes_received_w1_w2 BETWEEN 11 AND 20 THEN '11-20 pushes'
            ELSE '20+ pushes'
        END AS push_volume_bucket,

        CASE
            WHEN pushes_received_w1_w2 = 0 THEN 1
            WHEN pushes_received_w1_w2 BETWEEN 1 AND 5 THEN 2
            WHEN pushes_received_w1_w2 BETWEEN 6 AND 10 THEN 3
            WHEN pushes_received_w1_w2 BETWEEN 11 AND 20 THEN 4
            ELSE 5
        END AS bucket_order

    FROM push_volume
),

week4 AS (
    SELECT
        member_id,

        CASE
            WHEN weekly_adherence_pct >= 66.7 THEN 1
            ELSE 0
        END AS engaged_week4

    FROM outcomes
    WHERE week_number = 4
)

SELECT
    p.push_volume_bucket,

    COUNT(DISTINCT p.member_id) AS members,

    ROUND(
        AVG(1.0 * p.pushes_received_w1_w2),
        2
    ) AS avg_pushes_received_w1_w2,

    ROUND(
        100.0 * SUM(CASE WHEN w.engaged_week4 = 1 THEN 1 ELSE 0 END)
        / COUNT(DISTINCT p.member_id),
        2
    ) AS week4_engagement_from_initial_cohort_pct

FROM push_buckets p
LEFT JOIN week4 w
    ON p.member_id = w.member_id

GROUP BY
    p.push_volume_bucket,
    p.bucket_order

ORDER BY
    p.bucket_order;



-- ======================================================
-- 7. Early AI coach exposure vs Week 4 engagement
-- ======================================================
-- Shows that early AI coach exposure is associated with higher week 4 engagement.
-- This is correlational, not causal.

WITH ai_early AS (
    SELECT
        m.member_id,

        COUNT(CASE
            WHEN e.event_type = 'ai_coach_msg_sent'
             AND e.week_number BETWEEN 1 AND 2
            THEN e.event_id
        END) AS ai_messages_w1_w2

    FROM members m
    LEFT JOIN engagement_events e
        ON m.member_id = e.member_id

    GROUP BY m.member_id
),

ai_buckets AS (
    SELECT
        member_id,
        ai_messages_w1_w2,

        CASE
            WHEN ai_messages_w1_w2 = 0 THEN '0 AI messages'
            WHEN ai_messages_w1_w2 BETWEEN 1 AND 2 THEN '1-2 AI messages'
            WHEN ai_messages_w1_w2 BETWEEN 3 AND 5 THEN '3-5 AI messages'
            ELSE '6+ AI messages'
        END AS ai_message_bucket,

        CASE
            WHEN ai_messages_w1_w2 = 0 THEN 1
            WHEN ai_messages_w1_w2 BETWEEN 1 AND 2 THEN 2
            WHEN ai_messages_w1_w2 BETWEEN 3 AND 5 THEN 3
            ELSE 4
        END AS bucket_order

    FROM ai_early
),

week4 AS (
    SELECT
        member_id,

        CASE
            WHEN weekly_adherence_pct >= 66.7 THEN 1
            ELSE 0
        END AS engaged_week4

    FROM outcomes
    WHERE week_number = 4
)

SELECT
    a.ai_message_bucket,

    COUNT(DISTINCT a.member_id) AS members,

    ROUND(
        AVG(1.0 * a.ai_messages_w1_w2),
        2
    ) AS avg_ai_messages_w1_w2,

    ROUND(
        100.0 * SUM(CASE WHEN w.engaged_week4 = 1 THEN 1 ELSE 0 END)
        / COUNT(DISTINCT a.member_id),
        2
    ) AS week4_engagement_from_initial_cohort_pct

FROM ai_buckets a
LEFT JOIN week4 w
    ON a.member_id = w.member_id

GROUP BY
    a.ai_message_bucket,
    a.bucket_order

ORDER BY
    a.bucket_order;



-- ======================================================
-- 8. Exercise completion rate from sessions
-- ======================================================
-- Diagnostic check using the sessions table.
-- Shows that exercise completion declines modestly rather than collapsing.

SELECT
    week_number,

    COUNT(*) AS planned_exercise_sessions,

    SUM(CASE
        WHEN completed = 1 THEN 1
        ELSE 0
    END) AS completed_exercise_sessions,

    SUM(CASE
        WHEN completed = 0 THEN 1
        ELSE 0
    END) AS missed_exercise_sessions,

    ROUND(
        100.0 * SUM(CASE WHEN completed = 1 THEN 1 ELSE 0 END)
        / COUNT(*),
        2
    ) AS exercise_completion_rate_pct,

    ROUND(
        100.0 * SUM(CASE WHEN completed = 0 THEN 1 ELSE 0 END)
        / COUNT(*),
        2
    ) AS exercise_missed_rate_pct

FROM sessions
WHERE session_type = 'exercise'
  AND planned = 1
  AND week_number BETWEEN 1 AND 4
GROUP BY week_number
ORDER BY week_number;



-- ======================================================
-- 9. Clinical/session quality checks
-- ======================================================
-- Tests whether completed sessions appear to deteriorate.
-- Used to support the conclusion that the observed completed-session experience remains relatively stable.

SELECT
    week_number,

    COUNT(*) AS completed_exercise_sessions_with_pain_data,

    ROUND(
        AVG(pre_session_pain - post_session_pain),
        2
    ) AS avg_immediate_pain_reduction,

    ROUND(
        AVG(duration_min),
        2
    ) AS avg_completed_session_duration_min,

    ROUND(
        100.0 * SUM(CASE
            WHEN post_session_pain > pre_session_pain THEN 1
            ELSE 0
        END) / COUNT(*),
        2
    ) AS pct_sessions_pain_worse_after

FROM sessions
WHERE session_type = 'exercise'
  AND completed = 1
  AND week_number BETWEEN 1 AND 4
  AND pre_session_pain IS NOT NULL
  AND post_session_pain IS NOT NULL
GROUP BY week_number
ORDER BY week_number;



-- ======================================================
-- 10. Longitudinal pain change: first vs last completed exercise session
-- ======================================================
-- Used to check whether members who complete sessions show improvement over time.

WITH pain_sessions AS (
    SELECT
        member_id,
        session_id,
        session_date,
        week_number,
        pre_session_pain,
        post_session_pain,

        ROW_NUMBER() OVER (
            PARTITION BY member_id
            ORDER BY session_date, session_id
        ) AS rn_first,

        ROW_NUMBER() OVER (
            PARTITION BY member_id
            ORDER BY session_date DESC, session_id DESC
        ) AS rn_last

    FROM sessions
    WHERE session_type = 'exercise'
      AND completed = 1
      AND pre_session_pain IS NOT NULL
      AND post_session_pain IS NOT NULL
),

first_session AS (
    SELECT
        member_id,
        pre_session_pain AS first_pre_pain,
        post_session_pain AS first_post_pain
    FROM pain_sessions
    WHERE rn_first = 1
),

last_session AS (
    SELECT
        member_id,
        pre_session_pain AS last_pre_pain,
        post_session_pain AS last_post_pain
    FROM pain_sessions
    WHERE rn_last = 1
)

SELECT
    COUNT(DISTINCT f.member_id) AS members_with_first_and_last_pain_data,

    ROUND(AVG(f.first_pre_pain), 2) AS avg_first_pre_pain,
    ROUND(AVG(l.last_pre_pain), 2) AS avg_last_pre_pain,
    ROUND(AVG(f.first_pre_pain - l.last_pre_pain), 2) AS avg_pre_pain_reduction,

    ROUND(AVG(f.first_post_pain), 2) AS avg_first_post_pain,
    ROUND(AVG(l.last_post_pain), 2) AS avg_last_post_pain,
    ROUND(AVG(f.first_post_pain - l.last_post_pain), 2) AS avg_post_pain_reduction

FROM first_session f
INNER JOIN last_session l
    ON f.member_id = l.member_id;



-- ======================================================
-- 11. Referral source: Week 4 engagement from initial cohort
-- ======================================================
-- Strong segmentation signal used in the deck.
-- Clinician-referred members show higher week 4 engagement than self-paid members.

WITH initial_referral_cohort AS (
    SELECT
        referral_source,
        COUNT(DISTINCT member_id) AS initial_members
    FROM members
    GROUP BY referral_source
),

week4_engaged AS (
    SELECT
        m.referral_source,

        COUNT(DISTINCT CASE
            WHEN o.weekly_adherence_pct >= 66.7
            THEN o.member_id
        END) AS engaged_week4_members

    FROM members m
    LEFT JOIN outcomes o
        ON m.member_id = o.member_id
       AND o.week_number = 4

    GROUP BY m.referral_source
)

SELECT
    i.referral_source,
    i.initial_members,
    w.engaged_week4_members,

    ROUND(
        100.0 * w.engaged_week4_members / i.initial_members,
        2
    ) AS week4_engagement_from_initial_cohort_pct

FROM initial_referral_cohort i
INNER JOIN week4_engaged w
    ON i.referral_source = w.referral_source

ORDER BY week4_engagement_from_initial_cohort_pct DESC;



-- ======================================================
-- 12. Referral source: Week 2 engaged members retained as engaged in Week 4
-- ======================================================
-- Measures retention of the early exercise habit by referral source.

WITH week2 AS (
    SELECT
        m.referral_source,
        o.member_id,

        CASE
            WHEN o.weekly_adherence_pct >= 66.7 THEN 1
            ELSE 0
        END AS engaged_week2

    FROM outcomes o
    INNER JOIN members m
        ON o.member_id = m.member_id

    WHERE o.week_number = 2
),

week4 AS (
    SELECT
        member_id,

        CASE
            WHEN weekly_adherence_pct >= 66.7 THEN 1
            ELSE 0
        END AS engaged_week4

    FROM outcomes
    WHERE week_number = 4
)

SELECT
    w2.referral_source,

    COUNT(DISTINCT CASE
        WHEN w2.engaged_week2 = 1
        THEN w2.member_id
    END) AS engaged_week2_members,

    COUNT(DISTINCT CASE
        WHEN w2.engaged_week2 = 1
         AND w4.engaged_week4 = 1
        THEN w2.member_id
    END) AS retained_engaged_week4_members,

    COUNT(DISTINCT CASE
        WHEN w2.engaged_week2 = 1
         AND (w4.member_id IS NULL OR w4.engaged_week4 = 0)
        THEN w2.member_id
    END) AS no_longer_engaged_week4_members,

    ROUND(
        100.0 *
        COUNT(DISTINCT CASE
            WHEN w2.engaged_week2 = 1
             AND w4.engaged_week4 = 1
            THEN w2.member_id
        END)
        /
        COUNT(DISTINCT CASE
            WHEN w2.engaged_week2 = 1
            THEN w2.member_id
        END),
        2
    ) AS week2_engaged_retention_to_week4_pct

FROM week2 w2
LEFT JOIN week4 w4
    ON w2.member_id = w4.member_id

GROUP BY w2.referral_source
ORDER BY week2_engaged_retention_to_week4_pct DESC;



-- ======================================================
-- 13. Condition segmentation
-- ======================================================
-- Checks whether the drop is concentrated in a specific clinical condition.
-- Interpretation used in deck: condition patterns differ, but no single condition fully explains the overall drop.

WITH initial_condition_cohort AS (
    SELECT
        condition,
        COUNT(DISTINCT member_id) AS initial_members
    FROM members
    GROUP BY condition
),

engagement_by_week AS (
    SELECT
        m.condition,
        o.week_number,

        COUNT(DISTINCT CASE
            WHEN o.weekly_adherence_pct >= 66.7
            THEN o.member_id
        END) AS engaged_members

    FROM members m
    LEFT JOIN outcomes o
        ON m.member_id = o.member_id
       AND o.week_number BETWEEN 1 AND 4

    GROUP BY
        m.condition,
        o.week_number
)

SELECT
    e.condition,
    e.week_number,
    i.initial_members,
    e.engaged_members,

    ROUND(
        100.0 * e.engaged_members / i.initial_members,
        2
    ) AS engagement_from_initial_cohort_pct

FROM engagement_by_week e
INNER JOIN initial_condition_cohort i
    ON e.condition = i.condition

ORDER BY
    e.condition,
    e.week_number;



-- ======================================================
-- 14. Age band check
-- ======================================================
-- Tests whether week 4 engagement is materially different by age group.

WITH members_age_band AS (
    SELECT
        member_id,

        CASE
            WHEN age < 30 THEN '<30'
            WHEN age BETWEEN 30 AND 39 THEN '30-39'
            WHEN age BETWEEN 40 AND 49 THEN '40-49'
            WHEN age BETWEEN 50 AND 59 THEN '50-59'
            ELSE '60+'
        END AS age_band,

        CASE
            WHEN age < 30 THEN 1
            WHEN age BETWEEN 30 AND 39 THEN 2
            WHEN age BETWEEN 40 AND 49 THEN 3
            WHEN age BETWEEN 50 AND 59 THEN 4
            ELSE 5
        END AS age_band_order

    FROM members
),

initial_age_cohort AS (
    SELECT
        age_band,
        age_band_order,
        COUNT(DISTINCT member_id) AS initial_members
    FROM members_age_band
    GROUP BY age_band, age_band_order
),

week4_engaged AS (
    SELECT
        a.age_band,

        COUNT(DISTINCT CASE
            WHEN o.weekly_adherence_pct >= 66.7
            THEN o.member_id
        END) AS engaged_week4_members

    FROM members_age_band a
    LEFT JOIN outcomes o
        ON a.member_id = o.member_id
       AND o.week_number = 4

    GROUP BY a.age_band
)

SELECT
    i.age_band,
    i.initial_members,
    w.engaged_week4_members,

    ROUND(
        100.0 * w.engaged_week4_members / i.initial_members,
        2
    ) AS week4_engagement_from_initial_cohort_pct

FROM initial_age_cohort i
INNER JOIN week4_engaged w
    ON i.age_band = w.age_band

ORDER BY i.age_band_order;



-- ======================================================
-- 15. Region check
-- ======================================================
-- Tests whether region is a primary driver.
-- Interpretation used in deck: week 4 engagement from the initial cohort is broadly similar across regions.

WITH initial_region_cohort AS (
    SELECT
        region,
        COUNT(DISTINCT member_id) AS initial_members
    FROM members
    GROUP BY region
),

week4_engaged AS (
    SELECT
        m.region,

        COUNT(DISTINCT CASE
            WHEN o.weekly_adherence_pct >= 66.7
            THEN o.member_id
        END) AS engaged_week4_members

    FROM members m
    LEFT JOIN outcomes o
        ON m.member_id = o.member_id
       AND o.week_number = 4

    GROUP BY m.region
)

SELECT
    i.region,
    i.initial_members,
    w.engaged_week4_members,

    ROUND(
        100.0 * w.engaged_week4_members / i.initial_members,
        2
    ) AS week4_engagement_from_initial_cohort_pct

FROM initial_region_cohort i
INNER JOIN week4_engaged w
    ON i.region = w.region

ORDER BY week4_engagement_from_initial_cohort_pct ASC;



-- ======================================================
-- 16. Plan length check
-- ======================================================
-- Tests whether shorter plans have slightly higher week 4 engagement.

WITH initial_plan_cohort AS (
    SELECT
        plan_length_weeks,
        COUNT(DISTINCT member_id) AS initial_members
    FROM members
    GROUP BY plan_length_weeks
),

week4_engaged AS (
    SELECT
        m.plan_length_weeks,

        COUNT(DISTINCT CASE
            WHEN o.weekly_adherence_pct >= 66.7
            THEN o.member_id
        END) AS engaged_week4_members

    FROM members m
    LEFT JOIN outcomes o
        ON m.member_id = o.member_id
       AND o.week_number = 4

    GROUP BY m.plan_length_weeks
)

SELECT
    i.plan_length_weeks,
    i.initial_members,
    w.engaged_week4_members,

    ROUND(
        100.0 * w.engaged_week4_members / i.initial_members,
        2
    ) AS week4_engagement_from_initial_cohort_pct

FROM initial_plan_cohort i
INNER JOIN week4_engaged w
    ON i.plan_length_weeks = w.plan_length_weeks

ORDER BY i.plan_length_weeks;



-- ======================================================
-- 17. Churn by week
-- ======================================================
-- Checks explicit churn indicators.
-- Used for next steps and interpretation: churn reasons are not directly observed.

SELECT
    week_number,

    COUNT(DISTINCT member_id) AS members_in_outcomes,

    COUNT(DISTINCT CASE
        WHEN churned_this_week = 1
        THEN member_id
    END) AS churned_members,

    ROUND(
        100.0 * COUNT(DISTINCT CASE WHEN churned_this_week = 1 THEN member_id END)
        / COUNT(DISTINCT member_id),
        2
    ) AS churn_rate_among_observed_members_pct

FROM outcomes
WHERE week_number BETWEEN 1 AND 5
GROUP BY week_number
ORDER BY week_number;



-- ======================================================
-- 18. Check for events after churn
-- ======================================================
-- Used to understand the operational meaning of churned_this_week.
-- If this returns zero events, it suggests churned_this_week behaves like a final/terminal flag in the available data.

WITH churns AS (
    SELECT
        member_id,
        week_number AS churn_week
    FROM outcomes
    WHERE churned_this_week = 1
)

SELECT
    c.member_id,
    c.churn_week,

    COUNT(e.event_id) AS events_after_churn

FROM churns c
LEFT JOIN engagement_events e
    ON c.member_id = e.member_id
   AND e.week_number > c.churn_week

GROUP BY
    c.member_id,
    c.churn_week

ORDER BY events_after_churn DESC;



-- ======================================================
-- 19. Experiment baseline and MDE framing
-- ======================================================
-- Confirms the observed baseline used for the proposed A/B test.

WITH baseline AS (
    SELECT
        COUNT(DISTINCT m.member_id) AS initial_members,

        COUNT(DISTINCT CASE
            WHEN o.weekly_adherence_pct >= 66.7
            THEN o.member_id
        END) AS week4_engaged_members

    FROM members m
    LEFT JOIN outcomes o
        ON m.member_id = o.member_id
       AND o.week_number = 4
)

SELECT
    initial_members,
    week4_engaged_members,

    ROUND(
        100.0 * week4_engaged_members / initial_members,
        2
    ) AS baseline_week4_engagement_pct,

    ROUND(
        100.0 * (week4_engaged_members + 125.0) / initial_members,
        2
    ) AS approx_target_with_125_additional_members_pct,

    ROUND(
        (
            100.0 * (week4_engaged_members + 125.0) / initial_members
        )
        -
        (
            100.0 * week4_engaged_members / initial_members
        ),
        2
    ) AS approx_lift_pp

FROM baseline;