/* 
  Description:
  This SQL script performs end-to-end cleaning, transformation,
  and metric aggregation for deposit transactions. 
  It filters out spam sessions, assigns session IDs, 
  categorizes third-party channels by payment size, 
  and calculates success rates and deposit volume per provider.
  Optimized for monthly KPI reporting.

  Author: Dicky Setiawan

  FULL CTE BREAKDOWN EXPLANATION in README
*/

-- Step 1: Import deposit transaction data scoped to a specific month and categorize by payment size
WITH
deposit_monthly AS (
	SELECT
		depo.*,
		tp.min_payment,
		tp.max_payment,
		tp.transaction_rate,
		DATE_TRUNC('month', depo.order_time)::DATE AS month,
		CASE
			WHEN tp.max_payment <= 500 THEN 'Small Transactions'
			WHEN tp.max_payment <= 2000 THEN 'Medium Transactions'
			WHEN tp.max_payment <= 5000 THEN 'Large Transactions'
			ELSE 'All Transaction Sizes'
		END AS third_party_category,
		LAG(depo.order_time) OVER(PARTITION BY uid ORDER BY order_time ASC) AS prev_order_time
	FROM online_recharge_2025_01 AS depo
	LEFT JOIN online_recharge_third_party AS tp
		ON depo.third_party = tp.third_party
	WHERE DATE_TRUNC('month', depo.order_time)::DATE = Date '2025-01-01'
)
,
-- Step 2: Flag new sessions per UID based on time gap > 3 minutes
transaction_session AS (
	SELECT *,
		CASE
			WHEN prev_order_time IS NULL THEN 1
			WHEN EXTRACT(EPOCH FROM(order_time - prev_order_time)) / 60 > 3 THEN 1
			ELSE 0
		END AS new_session
	FROM deposit_monthly
)
,
-- Step 3: Assign running session ID per UID
transaction_session_id AS (
	SELECT *,
		SUM(new_session) OVER(PARTITION BY uid ORDER BY order_time) AS session_id
	FROM transaction_session
)
,
-- Step 4: Summarize each session, total orders and paid count
session_analysis AS (
	SELECT
		uid,
		session_id,
		COUNT(*) AS total_transaction,
		COUNT(*) FILTER (WHERE payment_status = 'Paid') AS paid_count
	FROM transaction_session_id
	GROUP BY uid, session_id
)
,
-- Step 5: Identify and exclude spam transaction from VIP 0 users
vip0_spammer AS (
	SELECT uid
	FROM transaction_session_id
	WHERE vip_level = 0
	GROUP BY uid
	HAVING 
		COUNT(*) >= 5 AND 
		COUNT(*) FILTER(WHERE payment_status = 'Paid') = 0
)
,
-- Step 6: Tag transaction as valid or invalid based on session logic
transaction_cleaned AS (
	SELECT
		tag.*,
		s.total_transaction,
		s.paid_count,
		CASE
			WHEN tag.uid IN (SELECT uid FROM vip0_spammer) THEN FALSE
			WHEN s.total_transaction >= 3 AND s.paid_count = 0 THEN FALSE
			ELSE TRUE
		END AS keep_transaction
	FROM transaction_session_id AS tag
	LEFT JOIN session_analysis AS s
		ON tag.uid = s.uid 
		AND tag.session_id = s.session_id
)
,
-- Step 7: Keep only valid transactions for KPI calculation
transaction_filtered  AS (
	SELECT *
	FROM transaction_cleaned
	WHERE keep_transaction = TRUE
)
,
-- Step 8: Aggregate final KPI metrics by each third_party
kpi_summary AS (
SELECT
    third_party,
    month,
    third_party_category,
    MIN(min_payment) AS min_payment,
    MAX(max_payment) AS max_payment,
    ROUND(MAX(transaction_rate) * 100, 2) AS transaction_rate,
    COUNT(*) AS total_order_number,
    SUM(
      CASE
        WHEN payment_status = 'Paid'
        AND paid_time IS NOT NULL
        AND EXTRACT(EPOCH FROM(paid_time - order_time)) / 3600 <= 72
        THEN 1 ELSE 0
      END
    ) AS total_success_within_72h,
    SUM(
      CASE
        WHEN payment_status = 'Paid' THEN amount
        WHEN payment_status = 'Manual' THEN amount
        ELSE 0
      END
    ) AS total_deposit_amount
  FROM transaction_filtered
  GROUP BY third_party, third_party_category, month
)
-- Step 9: Output final result with success rate calculation per third-party provider
SELECT *,
  ROUND((total_success_within_72h::NUMERIC / NULLIF(total_order_number, 0)) * 100, 2) AS success_rate
FROM kpi_summary
ORDER BY total_deposit_amount DESC;