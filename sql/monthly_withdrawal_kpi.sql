/* 
  Description:
  This SQL script processes and summarizes withdrawal transactions for monthly KPI tracking.
  It filters out records with invalid or missing timestamps,
  calculates processing speed (in minutes) between audit and notify time,
  and computes key metrics including total withdrawal volume and median processing time per provider.
  Results are grouped monthly and optimized for use in channel performance dashboards.

  Author: Dicky Setiawan
*/

-- Step 1: Prepare base dataset scoped to one month with calculated processing time
WITH withdrawal_monthly AS (
  SELECT
    third_party,
    withdrawal_amount,
    DATE_TRUNC('month', audit_time)::DATE AS month,
    EXTRACT(EPOCH FROM (notify_time - audit_time)) / 60 AS speed_minutes
  FROM withdrawal_2025_04
  WHERE
  	state = 'Approved'
	AND withdrawal_progress = 'Success'
    AND notify_time IS NOT NULL
    AND audit_time IS NOT NULL
    AND notify_time >= audit_time
    AND DATE_TRUNC('month', audit_time)::DATE = DATE '2025-04-01'
),

-- Step 2: Aggregate monthly KPIs by third-party provider
kpi_summary AS (
  SELECT
    month,
    third_party,
    COUNT(*) AS total_order_number,
    SUM(withdrawal_amount) AS total_withdrawal,
    ROUND(
      PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY CASE WHEN speed_minutes > 3 THEN speed_minutes ELSE NULL END)
    )::INT AS median_minutes
  FROM withdrawal_monthly
  GROUP BY third_party, month
)
-- Step 3: Output the final result sorted by withdrawal volume
SELECT 
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY median_minutes) AS median_minutes
FROM kpi_summary;