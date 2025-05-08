/*
  Description:
  This SQL script calculates the number of new users who made their first successful deposit 
  in a given month. It filters transactions where `first_recharge = 'Yes'` and payment was successful.
  Results are grouped and ordered by month to track acquisition trends over time.

  Author: Dicky Setiawan
*/

SELECT
	DATE_TRUNC('month', order_time)::DATE AS month,
	COUNT(DISTINCT uid) AS total_new_users_depositing
FROM online_recharge_2025_01
	WHERE first_recharge = 'Yes' 
	AND payment_status = 'Paid' 
	AND paid_time IS NOT NULL
GROUP BY 1
ORDER BY 1;