-- ========================================
-- RCM ANALYTICS: GOLD LEVEL QUERIES
-- Revenue Cycle Management Performance
-- ========================================

-- 1. COLLECTION TURNAROUND ANALYSIS
-- Track payment collection performance with aging buckets
WITH payment_aging AS (
    SELECT 
        f.TransactionID,
        f.ClaimID,
        f.Amount,
        f.PaidAmount,
        f.ServiceDate,
        f.PaidDate,
        d.Name AS Department,
        p.FirstName || ' ' || p.LastName AS Provider,
        CASE 
            WHEN f.PaidDate IS NULL THEN DATEDIFF(day, f.ServiceDate, CURRENT_DATE)
            ELSE DATEDIFF(day, f.ServiceDate, f.PaidDate)
        END AS days_to_payment,
        CASE 
            WHEN f.PaidDate IS NULL THEN 'Unpaid'
            WHEN DATEDIFF(day, f.ServiceDate, f.PaidDate) <= 30 THEN '0-30 days'
            WHEN DATEDIFF(day, f.ServiceDate, f.PaidDate) <= 60 THEN '31-60 days'
            WHEN DATEDIFF(day, f.ServiceDate, f.PaidDate) <= 90 THEN '61-90 days'
            ELSE '90+ days'
        END AS aging_bucket,
        CASE 
            WHEN f.PaidAmount IS NOT NULL AND f.PaidAmount > 0 THEN 'Paid'
            ELSE 'Outstanding'
        END AS payment_status
    FROM fact_transactions f
    LEFT JOIN dim_department d ON f.FK_DeptID = d.Dept_Id
    LEFT JOIN dim_provider p ON f.FK_ProviderID = p.ProviderID
    WHERE f.ServiceDate >= DATEADD(month, -12, CURRENT_DATE)
)
SELECT 
    aging_bucket,
    COUNT(*) AS transaction_count,
    SUM(Amount) AS total_billed,
    SUM(COALESCE(PaidAmount, 0)) AS total_collected,
    ROUND(SUM(COALESCE(PaidAmount, 0)) / SUM(Amount) * 100, 2) AS collection_rate,
    ROUND(AVG(days_to_payment), 1) AS avg_days_to_payment
FROM payment_aging
GROUP BY aging_bucket
ORDER BY 
    CASE aging_bucket
        WHEN '0-30 days' THEN 1
        WHEN '31-60 days' THEN 2
        WHEN '61-90 days' THEN 3
        WHEN '90+ days' THEN 4
        WHEN 'Unpaid' THEN 5
    END;

-- 2. AGED AR (ACCOUNTS RECEIVABLE) ANALYSIS
-- Track outstanding amounts by aging categories
WITH aged_ar AS (
    SELECT 
        f.TransactionID,
        f.ClaimID,
        f.Amount,
        f.PaidAmount,
        f.ServiceDate,
        f.PaidDate,
        d.Name AS Department,
        DATEDIFF(day, f.ServiceDate, CURRENT_DATE) AS days_outstanding,
        (f.Amount - COALESCE(f.PaidAmount, 0)) AS outstanding_amount,
        CASE 
            WHEN DATEDIFF(day, f.ServiceDate, CURRENT_DATE) <= 30 THEN 'Current (0-30)'
            WHEN DATEDIFF(day, f.ServiceDate, CURRENT_DATE) <= 60 THEN 'Past Due (31-60)'
            WHEN DATEDIFF(day, f.ServiceDate, CURRENT_DATE) <= 90 THEN 'Past Due (61-90)'
            WHEN DATEDIFF(day, f.ServiceDate, CURRENT_DATE) <= 120 THEN 'Past Due (91-120)'
            ELSE 'Past Due (120+)'
        END AS ar_aging_category
    FROM fact_transactions f
    LEFT JOIN dim_department d ON f.FK_DeptID = d.Dept_Id
    WHERE (f.Amount - COALESCE(f.PaidAmount, 0)) > 0  -- Only outstanding balances
)
SELECT 
    ar_aging_category,
    COUNT(*) AS claim_count,
    SUM(outstanding_amount) AS total_ar,
    ROUND(SUM(outstanding_amount) / SUM(SUM(outstanding_amount)) OVER() * 100, 2) AS ar_percentage,
    ROUND(AVG(outstanding_amount), 2) AS avg_outstanding_per_claim
FROM aged_ar
GROUP BY ar_aging_category
ORDER BY 
    CASE ar_aging_category
        WHEN 'Current (0-30)' THEN 1
        WHEN 'Past Due (31-60)' THEN 2
        WHEN 'Past Due (61-90)' THEN 3
        WHEN 'Past Due (91-120)' THEN 4
        WHEN 'Past Due (120+)' THEN 5
    END;

-- 3. MONTHLY COLLECTION PERFORMANCE BENCHMARK
-- Track collection rates and turnaround times by month
WITH monthly_performance AS (
    SELECT 
        FORMAT(f.ServiceDate, 'yyyy-MM') AS service_month,
        COUNT(*) AS total_transactions,
        SUM(f.Amount) AS total_billed,
        SUM(COALESCE(f.PaidAmount, 0)) AS total_collected,
        COUNT(CASE WHEN f.PaidDate IS NOT NULL AND DATEDIFF(day, f.ServiceDate, f.PaidDate) <= 30 THEN 1 END) AS paid_within_30,
        COUNT(CASE WHEN f.PaidDate IS NOT NULL AND DATEDIFF(day, f.ServiceDate, f.PaidDate) <= 60 THEN 1 END) AS paid_within_60,
        COUNT(CASE WHEN f.PaidDate IS NOT NULL AND DATEDIFF(day, f.ServiceDate, f.PaidDate) <= 90 THEN 1 END) AS paid_within_90,
        AVG(CASE WHEN f.PaidDate IS NOT NULL THEN DATEDIFF(day, f.ServiceDate, f.PaidDate) END) AS avg_collection_days
    FROM fact_transactions f
    WHERE f.ServiceDate >= DATEADD(month, -12, CURRENT_DATE)
    GROUP BY FORMAT(f.ServiceDate, 'yyyy-MM')
)
SELECT 
    service_month,
    total_transactions,
    total_billed,
    total_collected,
    ROUND(total_collected / total_billed * 100, 2) AS overall_collection_rate,
    ROUND(paid_within_30::FLOAT / total_transactions * 100, 2) AS pct_collected_30_days,
    ROUND(paid_within_60::FLOAT / total_transactions * 100, 2) AS pct_collected_60_days,
    ROUND(paid_within_90::FLOAT / total_transactions * 100, 2) AS pct_collected_90_days,
    ROUND(avg_collection_days, 1) AS avg_collection_days
FROM monthly_performance
ORDER BY service_month;

-- 4. DEPARTMENT PERFORMANCE COMPARISON
-- Compare collection performance across departments
WITH dept_performance AS (
    SELECT 
        d.Name AS Department,
        COUNT(*) AS total_claims,
        SUM(f.Amount) AS total_billed,
        SUM(COALESCE(f.PaidAmount, 0)) AS total_collected,
        COUNT(CASE WHEN f.PaidDate IS NOT NULL AND DATEDIFF(day, f.ServiceDate, f.PaidDate) <= 30 THEN 1 END) AS paid_within_30,
        COUNT(CASE WHEN f.PaidDate IS NOT NULL AND DATEDIFF(day, f.ServiceDate, f.PaidDate) <= 90 THEN 1 END) AS paid_within_90,
        SUM(CASE WHEN DATEDIFF(day, f.ServiceDate, CURRENT_DATE) > 90 AND (f.Amount - COALESCE(f.PaidAmount, 0)) > 0 THEN (f.Amount - COALESCE(f.PaidAmount, 0)) ELSE 0 END) AS ar_over_90_days,
        AVG(CASE WHEN f.PaidDate IS NOT NULL THEN DATEDIFF(day, f.ServiceDate, f.PaidDate) END) AS avg_collection_days
    FROM fact_transactions f
    JOIN dim_department d ON f.FK_DeptID = d.Dept_Id
    WHERE f.ServiceDate >= DATEADD(month, -6, CURRENT_DATE)
    GROUP BY d.Name
)
SELECT 
    Department,
    total_claims,
    ROUND(total_billed, 2) AS total_billed,
    ROUND(total_collected, 2) AS total_collected,
    ROUND(total_collected / total_billed * 100, 2) AS collection_rate,
    ROUND(paid_within_30::FLOAT / total_claims * 100, 2) AS pct_30_day_collection,
    ROUND(paid_within_90::FLOAT / total_claims * 100, 2) AS pct_90_day_collection,
    ROUND(ar_over_90_days, 2) AS ar_over_90_days,
    ROUND(avg_collection_days, 1) AS avg_collection_days,
    CASE 
        WHEN paid_within_30::FLOAT / total_claims >= 0.93 THEN 'Excellent'
        WHEN paid_within_30::FLOAT / total_claims >= 0.80 THEN 'Good'
        WHEN paid_within_30::FLOAT / total_claims >= 0.70 THEN 'Fair'
        ELSE 'Needs Improvement'
    END AS performance_rating
FROM dept_performance
ORDER BY collection_rate DESC;

-- 5. PROVIDER COLLECTION EFFICIENCY
-- Identify top and bottom performing providers
WITH provider_metrics AS (
    SELECT 
        p.FirstName || ' ' || p.LastName AS Provider,
        d.Name AS Department,
        COUNT(*) AS total_transactions,
        SUM(f.Amount) AS total_billed,
        SUM(COALESCE(f.PaidAmount, 0)) AS total_collected,
        COUNT(CASE WHEN f.PaidDate IS NOT NULL AND DATEDIFF(day, f.ServiceDate, f.PaidDate) <= 30 THEN 1 END) AS quick_collections,
        SUM(CASE WHEN (f.Amount - COALESCE(f.PaidAmount, 0)) > 0 AND DATEDIFF(day, f.ServiceDate, CURRENT_DATE) > 90 THEN (f.Amount - COALESCE(f.PaidAmount, 0)) ELSE 0 END) AS aged_ar,
        AVG(CASE WHEN f.PaidDate IS NOT NULL THEN DATEDIFF(day, f.ServiceDate, f.PaidDate) END) AS avg_collection_days
    FROM fact_transactions f
    JOIN dim_provider p ON f.FK_ProviderID = p.ProviderID
    JOIN dim_department d ON f.FK_DeptID = d.Dept_Id
    WHERE f.ServiceDate >= DATEADD(month, -6, CURRENT_DATE)
    GROUP BY p.FirstName, p.LastName, d.Name
    HAVING COUNT(*) >= 10  -- Only providers with significant volume
)
SELECT 
    Provider,
    Department,
    total_transactions,
    ROUND(total_collected / total_billed * 100, 2) AS collection_rate,
    ROUND(quick_collections::FLOAT / total_transactions * 100, 2) AS quick_collection_rate,
    ROUND(aged_ar, 2) AS aged_ar_amount,
    ROUND(avg_collection_days, 1) AS avg_collection_days
FROM provider_metrics
ORDER BY collection_rate DESC, quick_collection_rate DESC;

-- 6. CLAIM DENIAL AND REWORK ANALYSIS
-- Identify patterns in unpaid claims that may indicate denials
WITH claim_analysis AS (
    SELECT 
        f.ClaimID,
        f.Amount,
        f.PaidAmount,
        f.ServiceDate,
        f.PaidDate,
        f.VisitType,
        c.procedure_code_descriptions,
        i.code_description AS diagnosis_description,
        d.Name AS Department,
        CASE 
            WHEN f.PaidAmount IS NULL OR f.PaidAmount = 0 THEN 'Unpaid'
            WHEN f.PaidAmount < f.Amount THEN 'Partial Payment'
            ELSE 'Full Payment'
        END AS payment_status,
        DATEDIFF(day, f.ServiceDate, CURRENT_DATE) AS days_since_service
    FROM fact_transactions f
    LEFT JOIN dim_cpt_code c ON f.ProcedureCode = c.cpt_codes
    LEFT JOIN dim_icd i ON f.ICDCode = i.icd_code
    LEFT JOIN dim_department d ON f.FK_DeptID = d.Dept_Id
    WHERE f.ServiceDate >= DATEADD(month, -6, CURRENT_DATE)
)
SELECT 
    payment_status,
    COUNT(*) AS claim_count,
    ROUND(COUNT(*)::FLOAT / SUM(COUNT(*)) OVER() * 100, 2) AS percentage,
    SUM(Amount) AS total_amount,
    SUM(COALESCE(PaidAmount, 0)) AS total_paid,
    ROUND(AVG(days_since_service), 1) AS avg_days_outstanding
FROM claim_analysis
GROUP BY payment_status
ORDER BY claim_count DESC;

-- 7. CASH FLOW PROJECTION
-- Project collections based on historical patterns
WITH historical_patterns AS (
    SELECT 
        DATEDIFF(day, f.ServiceDate, f.PaidDate) AS days_to_payment,
        COUNT(*) AS frequency,
        SUM(f.PaidAmount) AS total_collected
    FROM fact_transactions f
    WHERE f.PaidDate IS NOT NULL 
    AND f.ServiceDate >= DATEADD(month, -12, CURRENT_DATE)
    AND DATEDIFF(day, f.ServiceDate, f.PaidDate) <= 180
    GROUP BY DATEDIFF(day, f.ServiceDate, f.PaidDate)
),
outstanding_claims AS (
    SELECT 
        f.TransactionID,
        f.Amount,
        f.ServiceDate,
        DATEDIFF(day, f.ServiceDate, CURRENT_DATE) AS days_outstanding,
        (f.Amount - COALESCE(f.PaidAmount, 0)) AS outstanding_amount
    FROM fact_transactions f
    WHERE (f.Amount - COALESCE(f.PaidAmount, 0)) > 0
    AND f.ServiceDate >= DATEADD(month, -6, CURRENT_DATE)
)
SELECT 
    'Next 30 Days' AS collection_period,
    COUNT(*) AS eligible_claims,
    SUM(outstanding_amount) AS potential_collections,
    ROUND(SUM(outstanding_amount) * 0.75, 2) AS projected_collections  -- 75% collection rate assumption
FROM outstanding_claims
WHERE days_outstanding <= 60
UNION ALL
SELECT 
    'Next 30-60 Days' AS collection_period,
    COUNT(*) AS eligible_claims,
    SUM(outstanding_amount) AS potential_collections,
    ROUND(SUM(outstanding_amount) * 0.50, 2) AS projected_collections  -- 50% collection rate assumption
FROM outstanding_claims
WHERE days_outstanding > 60 AND days_outstanding <= 90
UNION ALL
SELECT 
    'Beyond 60 Days' AS collection_period,
    COUNT(*) AS eligible_claims,
    SUM(outstanding_amount) AS potential_collections,
    ROUND(SUM(outstanding_amount) * 0.25, 2) AS projected_collections  -- 25% collection rate assumption
FROM outstanding_claims
WHERE days_outstanding > 90;

-- 8. KPI DASHBOARD SUMMARY
-- Executive summary of key RCM metrics
WITH kpi_summary AS (
    SELECT 
        COUNT(*) AS total_transactions,
        SUM(Amount) AS total_billed,
        SUM(COALESCE(PaidAmount, 0)) AS total_collected,
        COUNT(CASE WHEN PaidDate IS NOT NULL AND DATEDIFF(day, ServiceDate, PaidDate) <= 30 THEN 1 END) AS collected_30_days,
        COUNT(CASE WHEN PaidDate IS NOT NULL AND DATEDIFF(day, ServiceDate, PaidDate) <= 90 THEN 1 END) AS collected_90_days,
        SUM(CASE WHEN DATEDIFF(day, ServiceDate, CURRENT_DATE) > 90 AND (Amount - COALESCE(PaidAmount, 0)) > 0 THEN (Amount - COALESCE(PaidAmount, 0)) ELSE 0 END) AS aged_ar_90_plus,
        AVG(CASE WHEN PaidDate IS NOT NULL THEN DATEDIFF(day, ServiceDate, PaidDate) END) AS avg_collection_days
    FROM fact_transactions
    WHERE ServiceDate >= DATEADD(month, -3, CURRENT_DATE)
)
SELECT 
    'Current Quarter Performance' AS metric_period,
    total_transactions,
    ROUND(total_billed, 2) AS total_billed,
    ROUND(total_collected, 2) AS total_collected,
    ROUND(total_collected / total_billed * 100, 2) AS overall_collection_rate,
    ROUND(collected_30_days::FLOAT / total_transactions * 100, 2) AS pct_collected_30_days,
    ROUND(collected_90_days::FLOAT / total_transactions * 100, 2) AS pct_collected_90_days,
    ROUND(aged_ar_90_plus, 2) AS aged_ar_90_plus,
    ROUND(avg_collection_days, 1) AS avg_collection_days,
    CASE 
        WHEN collected_30_days::FLOAT / total_transactions >= 0.93 THEN 'Target Achieved'
        WHEN collected_30_days::FLOAT / total_transactions >= 0.73 THEN 'Approaching Target'
        ELSE 'Below Target'
    END AS performance_vs_target
FROM kpi_summary;