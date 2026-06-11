
--Create a staging table(loading everything as text, to avoid conversion error during import)  

DROP TABLE IF EXISTS dbo.fraud_stage;
GO

CREATE TABLE dbo.fraud_stage (
  step            VARCHAR(50),
  type            VARCHAR(20),
  amount          VARCHAR(50),
  nameOrig        VARCHAR(50),
  oldbalanceOrg   VARCHAR(50),
  newbalanceOrig  VARCHAR(50),
  nameDest        VARCHAR(50),
  oldbalanceDest  VARCHAR(50),
  newbalanceDest  VARCHAR(50),
  isFraud         VARCHAR(10),
  isFlaggedFraud  VARCHAR(10)
);
GO

--Bulk load load the CSV(fast and reliable)

BULK INSERT dbo.fraud_stage
FROM 'C:\bulkdata\Synthetic_Financial_datasets_log.csv'
WITH (
  FIRSTROW = 2,
  FIELDTERMINATOR = ',',
  ROWTERMINATOR = '0x0A',   -- <-- change here
  CODEPAGE = '65001',
  TABLOCK
);
GO

--Check if all columns were imported correctly

SELECT TOP 5 * FROM dbo.fraud_stage;

--Check if all rows were imported

SELECT COUNT(*) AS row_count FROM dbo.fraud_stage;

--Create final clean table(with proper datatypes)

DROP TABLE IF EXISTS dbo.fraud_transactions;
GO
CREATE TABLE dbo.fraud_transactions (
  step            INT,
  type            VARCHAR(20),
  amount          DECIMAL(28,2),
  nameOrig        VARCHAR(50),
  oldbalanceOrg   DECIMAL(28,2),
  newbalanceOrig  DECIMAL(28,2),
  nameDest        VARCHAR(50),
  oldbalanceDest  DECIMAL(28,2),
  newbalanceDest  DECIMAL(28,2),
  isFraud         BIT,
  isFlaggedFraud  BIT
);
GO

/* Convert safely
   'TRY_CONVERT' prevents the whole insert from failing(bad rows become 'null'
                 handles scientific notation
                    Scientific notation strings (like 1.916920493E7) convert cleanly via FLOAT first, then to DECIMAL*/

INSERT INTO dbo.fraud_transactions
SELECT
  TRY_CONVERT(INT, step),
  type,
  TRY_CONVERT(DECIMAL(28,2), TRY_CONVERT(FLOAT, amount)),
  nameOrig,
  TRY_CONVERT(DECIMAL(28,2), TRY_CONVERT(FLOAT, oldbalanceOrg)),
  TRY_CONVERT(DECIMAL(28,2), TRY_CONVERT(FLOAT, newbalanceOrig)),
  nameDest,
  TRY_CONVERT(DECIMAL(28,2), TRY_CONVERT(FLOAT, oldbalanceDest)),
  TRY_CONVERT(DECIMAL(28,2), TRY_CONVERT(FLOAT, newbalanceDest)),
  TRY_CONVERT(BIT, isFraud),
  TRY_CONVERT(BIT, isFlaggedFraud)
FROM dbo.fraud_stage;
GO

--Check if everythigh is transfered properly

SELECT * FROM fraud_transactions

--Calculate Total Txns, Fraud Txns and Fraud Rate

SELECT
  COUNT(*) AS total_txn,
  SUM(CASE WHEN isFraud = 1 THEN 1 ELSE 0 END) AS fraud_txn,
  CAST(100.0 * SUM(CASE WHEN isFraud = 1 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(10,4)) AS fraud_rate_pct
FROM dbo.fraud_transactions;

--Distinct Type of Txns

   select distinct(type) from fraud_transactions


--Calculate Total Txns, Fraud Txns and Fraud Rate on the basis of Type of Txn 

select
 type , 
 COUNT(*) as total_txn,
 SUM(case when isFraud = 1 then 1 else 0 end) as fraud_txn,
 cast(100.0 * SUM(case when isFraud = 1 then 1 else 0 end) as decimal(10,4)) / nullif(COUNT(*),0) as fraud_rate_pct
 from fraud_transactions
 group by type
 order by fraud_rate_pct desc

--Calculate Avg. Fraud Amount and Non-Fraud Amount  
 
 select
   type,
   AVG(case when isFraud = 1 then amount end) as Avg_Fraud_Amount,
   avg(case when isFraud = 0 then amount end) as Avg_NonFraud_Amount
   from fraud_transactions
   GROUP BY type
   ORDER BY Avg_Fraud_Amount desc,Avg_NonFraud_Amount desc

--Calculate No. of Mismatch and Total Txn on the basis of a specific rule for Fraud Txn 
   
   select COUNT(*) as total_TXN,
      COUNT(case when oldbalanceOrg - amount != newbalanceOrig then 1 end) as Mismatch_TXN
      from fraud_transactions
      where isFraud = 1

--Calculate No. of Mismatch and Total Txn on the basis of a specific rule for All Txn

   select COUNT(*) as total_TXN,
      COUNT(case when oldbalanceOrg - amount != newbalanceOrig then 1 end) as Mismatch_TXN
      from fraud_transactions
 
--Calculate No. of Mismatch and Total Txn on the basis of a specific rule for All Txn for CASH_OUT and TRANSFER type

   select TYPE ,
      COUNT(*) as total_TXN,
      COUNT(case when oldbalanceOrg - amount != newbalanceOrig then 1 end) as Mismatch_TXN,
      100.0 * COUNT(case when oldbalanceOrg - amount != newbalanceOrig then 1 end) / COUNT(*) AS mismatch_rate_pct
      from fraud_transactions
      where type in ('CASH_OUT' , 'TRANSFER')
      GROUP BY type

--Calculate Avg. Amount for Fraud and Non-Fraud Txns

   SELECT (case when isFraud = 1 then 'Fraud'  else 'Non-Fraud' end) as Fraud_TXN,
     AVG(amount) Avg_TXN_Amount
     from fraud_transactions
     group by isFraud

--Calculate Total_Txn, Fraud_Txn and % of Fraud_Txn on the basis of Amount Band

   select (case when amount between 0 and 10000 then 'lower band' else (case when amount between 10001 and 100000 then 'medium' else (case when amount between 100001 and 1000000 then 'high' else 'very high' end)end)end ) amount_band
   ,count(*) Total_TXN,
   sum(CASE WHEN isFraud = 1 then 1 else 0 end) Fraud_txn,
   100.0 * sum(CASE WHEN isFraud = 1 then 1 else 0 end) / count(*) Fraud_TXN_Pct
   from fraud_transactions
   group by (case when amount between 0 and 10000 then 'lower band' else (case when amount between 10001 and 100000 then 'medium' else (case when amount between 100001 and 1000000 then 'high' else 'very high' end)end)end )

--Calculate Total_Txn, Fraud_Txn and % of Fraud_Txn for type in ('CASH_OUT' , 'TRANSFER') and amount >= 1M

   select count(*) Total_TXN,
   sum(CASE WHEN isFraud = 1 then 1 else 0 end) Fraud_txn,
   100.0 * sum(CASE WHEN isFraud = 1 then 1 else 0 end) / count(*) Fraud_TXN_Pct
   from fraud_transactions
   where type in ('CASH_OUT' , 'TRANSFER') and  amount >= 1000000

--Calculate Total_Txn, Fraud_Txn and % of Fraud_Txn for type in ('CASH_OUT' , 'TRANSFER') and amount >= 1M and New Balance < 1000

  select count(*) Total_TXN,
   sum(CASE WHEN isFraud = 1 then 1 else 0 end) Fraud_txn,
   100.0 * sum(CASE WHEN isFraud = 1 then 1 else 0 end) / count(*) Fraud_TXN_Pct
   from fraud_transactions
   where type in ('CASH_OUT' , 'TRANSFER') and  amount >= 1000000 and newbalanceOrig <1000

--

   select t1.nameDest , t2.nameOrig , t2.amount
   from fraud_transactions t1 left join fraud_transactions t2
   on t1.nameDest = t2.nameOrig
   where t1.type in ('TRANSFER') AND t2.type In ('CASH_OUT')
   AND (t2.step between t1.step and t1.step + 2)

--

    select  t1.nameDest , t2.nameOrig , t2.amount , t1.isFraud , t2.isFraud
   from fraud_transactions t1 left join fraud_transactions t2
   on t1.nameDest = t2.nameOrig
   where t1.type in ('TRANSFER') AND t2.type In ('CASH_OUT')
   AND t2.step between t1.step and t1.step + 2

--Calculate Percentage Share of each Type of Txn in Fraud Txn

   select type,
   count(case when isFraud = 1 then 1 end) Fraud_txn,
   100.0 * count(case when isFraud = 1 then 1 end) / SUM(COUNT(CASE WHEN isFraud = 1 THEN 1 END)) OVER() AS fraud_share_pct
   from fraud_transactions
   group by type
   order by Fraud_txn

--How good is Flagged Fraud

   select
    count(case when isFlaggedFraud = 1 and isFraud = 1 then 1 end) as 'true positives' ,
    count(case when isFlaggedFraud = 1 and isFraud = 0 then 1 end) as 'false positives' ,
    count(case when isFlaggedFraud = 0 and isFraud = 1 then 1 end) as 'false negatives' ,
    count(case when isFlaggedFraud = 0 and isFraud = 0 then 1 end) as 'true negatives'
   from fraud_transactions

--Precision and Recall

   select 
   1.0 * count(case when isFlaggedFraud = 1 and isFraud = 1 then 1 end) / (count(case when isFlaggedFraud = 1 and isFraud = 1 then 1 end) + count(case when isFlaggedFraud = 1 and isFraud = 0 then 1 end)) 'Precision',
   1.0 * count(case when isFlaggedFraud = 1 and isFraud = 1 then 1 end) / (count(case when isFlaggedFraud = 1 and isFraud = 1 then 1 end) + count(case when isFlaggedFraud = 0 and isFraud = 1 then 1 end)) 'Recall'
   from fraud_transactions

--Calculate avg_amount, avg_oldbalanceOrg and avg_newbalanceOrig for flagged and non-flagged txns

   select  isFlaggedFraud, 
           AVG(amount) 'avg_amount', 
           AVG(oldbalanceOrg) 'avg_oldbalanceOrg', 
           AVG(newbalanceOrig) 'avg_newbalanceOrig'
   from fraud_transactions
   where isFraud = 1
   group by isFlaggedFraud

--Calculate Fraud txn, Flagged Fraud txn and % of Fraud Flagged on the basis of Amount Band

   select (case when amount >= 1000000 then '>=1M' 
                   when amount >=100000 then '100k ~ 1M'
                   When amount >= 10000 then '10k ~ 100k'
                   else '0 ~ 10k' end) Amount_Band ,
    count(*) Fraud_txn,
    count(case when isFlaggedFraud = 1 then 1 end) Flagged_Fraud_txn,
    100.0 * count(case when isFlaggedFraud = 1 then 1 end) / count(*) pct_Fraud_Flagged
    from fraud_transactions
    where isFraud = 1
    group by (case when amount >= 1000000 then '>=1M' 
                   when amount >=100000 then '100k ~ 1M'
                   When amount >= 10000 then '10k ~ 100k'
                   else '0 ~ 10k' end) 

--Calculate Fraud txn, Total txn and % of Fraud txn on the basis of Amount Band and type in ('TRANSFER','CASH_OUT')

    select (case when amount >= 1000000 then '>=1M' 
                   when amount >=100000 then '100k ~ 1M'
                   When amount >= 10000 then '10k ~ 100k'
                   else '0 ~ 10k' end) Amount_Band ,
        type ,
        count(*) Total_TXN,
        count(case when isFraud = 1 then 1 end) Fraud_TXN,
        100.0 * count(case when isFraud = 1 then 1 end) / count(*) Fraud_Rate_pct
        from fraud_transactions
        where type in ('TRANSFER','CASH_OUT')
        group by type , (case when amount >= 1000000 then '>=1M' 
                   when amount >=100000 then '100k ~ 1M'
                   When amount >= 10000 then '10k ~ 100k'
                   else '0 ~ 10k' end)
        order by Fraud_Rate_pct desc

