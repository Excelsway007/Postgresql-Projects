CREATE TABLE "nexa_sat".nexa_sat(
       Customer_id VARCHAR(50),
	   gender VARCHAR(10),
	   Partner VARCHAR(3),
		Dependents VARCHAR(3),
		Senior_Citizen INT,
		Call_Duration FLOAT,
		Data_Usage FLOAT,
		Plan_Type VARCHAR(20),
		Plan_Level VARCHAR(20),
		Monthly_Bill_Amount FLOAT,
		Tenure_Months INT,
		Multiple_Lines VARCHAR(3),
		Tech_Support VARCHAR(3),
		Churn INT);
		
SELECT current_schema();
SET search_path TO "nexa_sat";

SELECT * FROM nexa_sat;

SELECT Customer_id ,
	   gender,
	   Partner ,
		Dependents ,
		Senior_Citizen,
		Call_Duration ,
		Data_Usage,
		Plan_Type ,
		Plan_Level ,
		Monthly_Bill_Amount,
		Tenure_Months,
		Multiple_Lines,
		Tech_Support,
		Churn 
FROM nexa_sat
group  by Customer_id ,
	   gender,
	   Partner ,
		Dependents ,
		Senior_Citizen,
		Call_Duration ,
		Data_Usage,
		Plan_Type ,
		Plan_Level ,
		Monthly_Bill_Amount,
		Tenure_Months,
		Multiple_Lines,
		Tech_Support,
		Churn 
having count(*)>1;

SELECT ROUND(CAST(SUM(monthly_bill_amount) AS NUMERIC), 2) revenue
from nexa_sat

SELECT plan_level, ROUND(CAST(SUM(monthly_bill_amount) AS NUMERIC), 2) revenue
from nexa_sat
group by 1
order by 1

SELECT plan_level, plan_type, count(*) as  total_customers,sum(churn) churn_count
from nexa_sat
group by 1,2
order by 3

--avg tenure by plan level
SELECT plan_level, ROUND(AVG(tenure_months),2) avg_tenure
from nexa_sat
group by 1


SELECT plan_type, plan_level, ROUND(CAST(SUM(data_usage)AS NUMERIC),2) DATA_SUM
from nexa_sat
where churn = 0
group by 1,2
order by 3 desc

--gender that makes the most call
SELECT gender, ROUND(CAST(SUM(call_duration)AS NUMERIC),2) tot_call_duration
from nexa_sat
group by 1
order by 2 desc

select tenure_months,customer_id from nexa_sat

--Segments
CREATE TABLE existing_users AS
select *
from nexa_sat
where churn = 0;

SELECT *
from existing_users;

--create rev per existing user(ARPU)
SELECT ROUND(AVG(monthly_bill_amount::INT), 2) ARPUT
FROM existing_users;


--CALC CLV and add column
ALTER TABLE existing_users
ADD COLUMN clv FLOAT;

UPDATE existing_users
SET clv = monthly_bill_amount * tenure_months;

--view new clv col.
SELECT customer_id, clv
FROM existing_users;

--clv score(monthly bill=40%, tenure =30%, call_dur=10%,data usage= 10%,premium=10%)
ALTER TABLE existing_users
ADD COLUMN clv_score NUMERIC(10,2);

UPDATE existing_users
SET clv_score =
 				(0.4 * monthly_bill_amount)+
				(0.3 * tenure_months)+
				(0.1 * call_duration)+
				(0.1 * data_usage)+
				(0.1 * CASE WHEN plan_level = 'Premium' THEN 1 else 0 END);
				
--NEW clv score column
SELECT customer_id, clv_score
from existing_users;


--group users into segments based on clv scores
ALTER TABLE existing_users
ADD COLUMN clv_segments VARCHAR;

UPDATE existing_users
SET clv_segments =
			CASE WHEN clv_score>(SELECT percentile_cont(0.85)
								within group (order by clv_score) from existing_users) THEN 'High Value'
				 when clv_score>=(SELECT percentile_cont(0.50)
								within group (order by clv_score) from existing_users) THEN 'Moderate Value'
				when clv_score>=(SELECT percentile_cont(0.25)
								within group (order by clv_score) from existing_users) THEN 'low Value'
				ELSE 'Churn Risk'
				END;
				
--view segments
SELECT customer_id, clv, clv_score, clv_segments
FROM existing_users;

--analyzing the segments
--avg bill and tenure per segment
SELECT clv_segments, ROUND(AVG(monthly_bill_amount::INT),2)  average_monthly_charges,
ROUND(AVG(tenure_months::INT),2) avg_tenure
from existing_users
group by 1



--tech support and multiple lines count
SELECT clv_segments, ROUND(AVG(CASE WHEN tech_support = 'Yes' THEN 1 ELSE 0 END),2) tech_supprt_pct,
ROUND(AVG(CASE WHEN multiple_lines = 'Yes' THEN 1 ELSE 0 END),2) multiple_line_pcntg
FROM existing_users
group by 1;



--revenue per segment
SELECT clv_segments, COUNT(customer_id) number_of_customers,
		(sum(monthly_bill_amount * tenure_months)::NUMERIC(10,2)) total_revenue
from existing_users
group by 1;
		

-- crross selling and up selling
--cross selling: tech support to snr citizens
SELECT customer_id
from existing_users
where senior_citizen = 1 --elderly people
AND dependents = 'No'  --no tech inclined person to guide them
AND tech_support = 'No' --people without tech support
AND (clv_segments = 'Churn Risk' OR clv_segments = 'low Value');

--cross selling- multiple lines for partners and dependents
SELECT customer_id
from existing_users
where multiple_lines = 'No'
AND (dependents = 'Yes' or partner = 'Yes')
AND plan_level = 'Basic';

--upselling: premium discount for basic users with churn risk
SELECT customer_id
from existing_users
where clv_segments = 'Churn Risk'
AND plan_level = 'Basic';

--upselling- basic to premium for longer lock in period and higher arpu
SELECT plan_level, ROUND(AVG(monthly_bill_amount)::INT,2) average_bill, ROUND(AVG(tenure_months)::INT,2) average_tenure
from existing_users
where clv_segments = 'High Value'
OR clv_segments = 'Moderate Value'
group by 1;

--select customers
SELECT customer_id, monthly_bill_amount
from existing_users
where plan_level = 'Basic'
AND (clv_segments='High Value' or clv_segments='Moderate Value')
AND monthly_bill_amount>150;

--offer churned customers discounted plan,exclusive offers and upgrades to get them hooked
SELECT COUNT(churn) former_users
from nexa_sat
where churn = 1 


--CREATE stored procedures
--Snr citizens to be offerred tech support
CREATE FUNCTION tech_support_snr_ctzn()
RETURNs TABLE (customer_id VARCHAR(50))
AS $$
BEGIN
	RETURN QUERY
	SELECT eu.customer_id
	from existing_users eu
	where eu.senior_citizen = 1 --elderly people
	AND eu.dependents = 'No'  --no tech inclined person to guide them
	AND eu.tech_support = 'No' --people without tech support
	AND (eu.clv_segments = 'Churn Risk' OR eu.clv_segments = 'low Value');
END;
$$ LANGUAGE plpgsql;

--churn risk customers to be offered premium disc.
CREATE FUNCTION  churn_risk_discount()	
RETURNS TAbLE(customer_id VARCHAR(50))
AS $$
BEGIN
	RETURN QUERY
	SELECT eu.customer_id
	from existing_users eu
	where eu.clv_segments = 'Churn Risk'
	AND eu.plan_level = 'Basic';
END;
$$ LANGUAGE plpgsql;

--high usage basic customers to be offered premium upgrade
CREATE FUNCTION high_usage_basic()
RETURNS TABLE (customer_id VARCHAR(50))
AS $$
BEGIN
	RETURN QUERY
	SELECT eu.customer_id
	from existing_users eu
	where eu.plan_level = 'Basic'
	AND (eu.clv_segments='High Value' or eu.clv_segments='Moderate Value')
	AND eu.monthly_bill_amount>150;
END;
$$ LANGUAGE plpgsql;

--function for multiple lines for dependents and partners
CREATE FUNCTION multiple_lines_dp()
RETURNs TABLE(customer_id VARCHAR(3))
AS $$
BEGIN
	RETURN QUERY
	SELECT eu.customer_id
	from existing_users eu
	where eu.multiple_lines = 'No'
	AND (eu.dependents = 'Yes' or eu.partner = 'Yes')
	AND eu.plan_level = 'Basic';
END;
$$ LANGUAGE plpgsql;

--TEST procedures
--churn risk disc
SELECT *
FROM churn_risk_disc();

--high usage basic
SELECT *
FROM high_usage_basic()

--multiple lines for dependents and partners
SELECT *
FROM multiple_lines_dp()


--avg data usage and call duration for each plan level
SELECT plan_level, AVG(call_duration) avg_call_duration, AVG(data_usage) avg_data_usage
from existing_users
group by 1

