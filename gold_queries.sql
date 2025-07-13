SELECT
  CONCAT(p.FirstName, ' ', p.LastName) AS Provider_Name,
  dd.Name AS Dept_Name,
  SUM(ft.Amount) AS Total_Charge_Amt
FROM
  gold.fact_transactions ft
  LEFT JOIN gold.dim_provider p ON p.ProviderID = ft.FK_ProviderID
  LEFT JOIN gold.dim_department dd ON dd.Dept_Id = p.DeptID
GROUP BY
  Provider_Name, Dept_Name;


SELECT
  CONCAT(p.FirstName, ' ', p.LastName) AS Provider_Name,
  dd.Name AS Dept_Name,
  DATE_FORMAT(ft.ServiceDate, '%Y%m') AS YYYYMM,
  SUM(ft.Amount) AS Total_Charge_Amt,
  SUM(ft.PaidAmount) AS Total_Paid_Amt
FROM
  gold.fact_transactions ft
  LEFT JOIN gold.dim_provider p ON p.ProviderID = ft.FK_ProviderID
  LEFT JOIN gold.dim_department dd ON dd.Dept_Id = p.DeptID
WHERE
  YEAR(ft.ServiceDate) = 2024
GROUP BY
  Provider_Name, Dept_Name, YYYYMM
ORDER BY
  Provider_Name, YYYYMM;
