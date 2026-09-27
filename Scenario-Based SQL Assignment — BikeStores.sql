
--Scenario-Based SQL Assignment — BikeStores

--Assignment Tasks

--Task 1 — Build the Sales Detail Dataset (6 marks)
--Management needs a detailed sales dataset for analysis. Return one row per order item containing:
--order_id and order_date
--customer full name
--store name
--staff full name
--product name
--category name
--brand name
--quantity, list_price, discount
--calculated net_line_revenue
--Include only completed orders (order_status = 4). Sort the result from newest order to oldest.

SELECT
    o.order_id,
    o.order_date,
    c.first_name + ' ' + c.last_name           AS customer_name,
    st.store_name,
    s.first_name + ' ' + s.last_name           AS staff_name,
    p.product_name,
    cat.category_name,
    b.brand_name,
    oi.quantity,
    oi.list_price,
    oi.discount,
    oi.quantity * oi.list_price * (1 - oi.discount) AS net_line_revenue
FROM sales.orders AS o
INNER JOIN sales.order_items AS oi
    ON o.order_id = oi.order_id
INNER JOIN sales.customers AS c
    ON o.customer_id = c.customer_id
INNER JOIN sales.stores AS st
    ON o.store_id = st.store_id
INNER JOIN sales.staffs AS s
    ON o.staff_id = s.staff_id
INNER JOIN production.products AS p
    ON oi.product_id = p.product_id
INNER JOIN production.categories AS cat
    ON p.category_id = cat.category_id
INNER JOIN production.brands AS b
    ON p.brand_id = b.brand_id
WHERE o.order_status = 4  
ORDER BY o.order_date DESC;

--Task 2 — Store Performance Summary (5 marks)
--Create a store-level performance report for completed orders showing:
--store name
--number of distinct orders
--total units sold
--total net revenue
--average order value
--Return one row per store and order the stores from highest to lowest total net revenue.

WITH order_level AS (
    -- Step 1: Collapse all order items to the one row per order,calculating units and net revenue per order
    SELECT
        o.store_id,
        o.order_id,
        SUM(oi.quantity)                                  AS order_units,
        SUM(oi.quantity * oi.list_price * (1 - oi.discount)) AS order_net_revenue
    FROM sales.orders AS o
    INNER JOIN sales.order_items AS oi
        ON o.order_id = oi.order_id
    WHERE o.order_status = 4   --Completed orders only
    GROUP BY o.store_id, o.order_id
)

--Step 2: Aggregate order level results up to store level results
SELECT
    st.store_name,
    COUNT(DISTINCT ol.order_id)                    AS distinct_orders,
    SUM(ol.order_units)                             AS total_units_sold,
    SUM(ol.order_net_revenue)                       AS total_net_revenue,
    SUM(ol.order_net_revenue) / COUNT(DISTINCT ol.order_id) AS average_order_value
FROM order_level AS ol
INNER JOIN sales.stores AS st
    ON ol.store_id = st.store_id
GROUP BY st.store_name
ORDER BY total_net_revenue DESC;


--Task 3 — High-Value Customers (5 marks)
--Management wants to identify high-value customers. Return customers whose total completed-order spending is greater than the average total spending of customers who have completed orders.
--Show customer_id, customer name, completed order count, and total spending. Order the result by total spending descending.

WITH customer_spending AS (
    -- Step 1: Total spending and completed order count per customer
    SELECT
        c.customer_id,
        c.first_name + ' ' + c.last_name              AS customer_name,
        COUNT(DISTINCT o.order_id)                     AS completed_order_count,
        SUM(oi.quantity * oi.list_price * (1 - oi.discount)) AS total_spending
    FROM sales.customers AS c
    INNER JOIN sales.orders AS o
        ON c.customer_id = o.customer_id
    INNER JOIN sales.order_items AS oi
        ON o.order_id = oi.order_id
    WHERE o.order_status = 4   -- Completed orders only
    GROUP BY c.customer_id, c.first_name, c.last_name
)
-- Step 2: Keep only customers above the average total spending
SELECT
    customer_id,
    customer_name,
    completed_order_count,
    total_spending
FROM customer_spending
WHERE total_spending > (
    SELECT AVG(total_spending)
    FROM customer_spending
)
ORDER BY total_spending DESC;


--Task 4 — Inventory Risk Report (5 marks)
--Operations wants to identify inventory risk. Return products where the stock quantity is below 5 in at least one store.
--Show product name, store name, current quantity, category name, and brand name. Products with zero stock should appear first, followed by the lowest remaining quantities.

SELECT 
    p.product_name,
    st.store_name,
    s.quantity                     AS current_quantity,
    cat.category_name,
    b.brand_name
FROM production.stocks AS s
INNER JOIN production.products AS p
    ON s.product_id = p.product_id
INNER JOIN production.categories AS cat
    ON p.category_id = cat.category_id
INNER JOIN production.brands AS b
    ON p.brand_id = b.brand_id
INNER JOIN sales.stores AS st
    ON s.store_id = st.store_id
WHERE s.quantity < 5  
ORDER BY s.quantity ASC; 


--Task 5 — Top Products Within Each Category (6 marks)
--For each product category, identify the top 3 products by total net revenue from completed orders.
--Return category name, product name, total units sold, total net revenue, and the product's position within its category. Tied products must receive the same position and the next position should not contain gaps.
 
 WITH ProductRevenue AS (
    SELECT 
        c.category_name,
        p.product_name,
        SUM(oi.quantity) AS total_units_sold,
        SUM(oi.quantity * oi.list_price * (1 - oi.discount)) AS total_net_revenue
    FROM production.categories c
    JOIN production.products p 
        ON c.category_id = p.category_id
    JOIN sales.order_items oi 
        ON p.product_id = oi.product_id
    JOIN sales.orders o 
        ON oi.order_id = o.order_id
    WHERE o.order_status = 4 
    GROUP BY 
        c.category_name,
        p.product_name
),
RankedProducts AS (
    SELECT 
        category_name,
        product_name,
        total_units_sold,
        total_net_revenue,
        DENSE_RANK() OVER (
            PARTITION BY category_name 
            ORDER BY total_net_revenue DESC
        ) AS position
    FROM ProductRevenue
)
SELECT 
    category_name,
    product_name,
    total_units_sold,
    CAST(total_net_revenue AS DECIMAL(18, 2)) AS total_net_revenue,
    position
FROM RankedProducts
WHERE position <= 3
ORDER BY 
    category_name ASC, 
    position ASC;


--Task 6 — Monthly Sales Trend (6 marks)
--Create a monthly sales trend for completed orders.

--For each calendar month return:
--year
--month
--total net revenue
--previous month's total net revenue
--revenue change from the previous month
--The first month may have NULL for the previous-month comparison. Sort chronologically.

WITH MonthlyRevenue AS (
    SELECT 
        YEAR(o.order_date) AS [year],
        MONTH(o.order_date) AS [month],
        SUM(oi.quantity * oi.list_price * (1 - oi.discount)) AS total_net_revenue
    FROM sales.orders o
    JOIN sales.order_items oi 
        ON o.order_id = oi.order_id
    WHERE o.order_status = 4 
    GROUP BY 
        YEAR(o.order_date),
        MONTH(o.order_date)
)
SELECT 
    [year],
    [month],
    CAST(total_net_revenue AS DECIMAL(18, 2)) AS total_net_revenue,
    CAST(LAG(total_net_revenue) OVER (ORDER BY [year], [month]) AS DECIMAL(18, 2)) AS previous_month_revenue,
    CAST(total_net_revenue - LAG(total_net_revenue) OVER (ORDER BY [year], [month]) AS DECIMAL(18, 2)) AS revenue_change
FROM MonthlyRevenue
ORDER BY 
    [year] ASC, 
    [month] ASC;


--Task 7 — Reusable Reporting View (4 marks)
--Create a view named sales.vw_customer_sales_summary that returns one row per customer and includes:
--customer_id
--customer full name
--total number of completed orders
--total units purchased
--total net revenue
--most recent completed order date
--Customers with no completed orders must still be represented where possible, with appropriate zero/NULL values.


GO
CREATE OR ALTER VIEW sales.vw_customer_sales_summary AS
SELECT 
    c.customer_id,
    c.first_name + ' ' + c.last_name AS customer_full_name,
    COUNT(DISTINCT o.order_id) AS total_completed_orders,
    ISNULL(SUM(oi.quantity), 0) AS total_units_purchased,
    CAST(ISNULL(SUM(oi.quantity * oi.list_price * (1 - oi.discount)), 0) AS DECIMAL(18, 2)) AS total_net_revenue,
    MAX(o.order_date) AS most_recent_completed_order_date
FROM sales.customers c
LEFT JOIN sales.orders o 
    ON c.customer_id = o.customer_id 
    AND o.order_status = 4 
LEFT JOIN sales.order_items oi 
    ON o.order_id = oi.order_id
GROUP BY 
    c.customer_id,
    c.first_name,
    c.last_name;

Go

--Task 8 — Safe Data Modification (4 marks)
--A customer with customer_id = 1 has requested that their phone number be changed to '(999) 555-0101'.
--Write SQL that performs this update inside an explicit transaction. Include a validation query after the UPDATE and show how the change can be rolled back during testing so the assessment database is not permanently changed.

--Start a explicit transaction
BEGIN TRANSACTION;

--Perform the requested data modification

UPDATE sales.customers
SET phone = '(999) 555-0101'
WHERE customer_id = 1;

--Validation query to prove the update worked within the transaction
SELECT 
    customer_id, 
    first_name, 
    last_name, 
    phone 
FROM sales.customers
WHERE customer_id = 1;

--Rollback the transaction so the database is not permanently changed
ROLLBACK TRANSACTION;

--Task 9 — Store Sales Procedure (6 marks)
--Create a stored procedure named sales.usp_store_sales_report with these input parameters:
--@store_id
--@start_date
--@end_date
--The procedure should return completed-order sales for the requested store and date range, grouped by product. Return product name, total units sold, and total net revenue, ordered by revenue descending.
--Add appropriate error handling for invalid date ranges where @start_date is later than @end_date.

GO
CREATE OR ALTER PROCEDURE sales.usp_store_sales_report
    @store_id INT,
    @start_date DATE,
    @end_date DATE
AS
BEGIN
    SET NOCOUNT ON;

   
    IF @start_date > @end_date
    BEGIN
        
        ;THROW 50000, 'Invalid date range: @start_date cannot be later than @end_date.', 1;
        RETURN;
    END

  
    SELECT 
        p.product_name,
        SUM(oi.quantity) AS total_units_sold,
        CAST(SUM(oi.quantity * oi.list_price * (1 - oi.discount)) AS DECIMAL(18, 2)) AS total_net_revenue
    FROM sales.orders o
    JOIN sales.order_items oi 
        ON o.order_id = oi.order_id
    JOIN production.products p 
        ON oi.product_id = p.product_id
    WHERE o.store_id = @store_id
      AND o.order_status = 4 -- Assuming 4 represents 'Completed' orders
      AND o.order_date >= @start_date
      AND o.order_date <= @end_date
    GROUP BY 
        p.product_name
    ORDER BY 
        total_net_revenue DESC;
END;


--Task 10 — Management Insight Query (3 marks)
--Write one additional SQL query that you believe would provide useful insight to BikeStores management using at least three tables.

--Below the query, add a SQL comment of no more than three lines explaining:
--1. the business question,
--2. what the result measures, and
--3. why management should care about it.

SELECT 
    str.store_name,
    st.first_name + ' ' + st.last_name AS staff_name,
    COUNT(DISTINCT o.order_id) AS total_orders_processed,
    CAST(SUM(oi.quantity * oi.list_price * (1 - oi.discount)) AS DECIMAL(18, 2)) AS total_revenue_generated
FROM sales.staffs st
JOIN sales.stores str 
    ON st.store_id = str.store_id
JOIN sales.orders o 
    ON st.staff_id = o.staff_id
JOIN sales.order_items oi 
    ON o.order_id = oi.order_id
WHERE o.order_status = 4 -- Only counting completed orders
GROUP BY 
    str.store_name, 
    st.first_name, 
    st.last_name
ORDER BY 
    total_revenue_generated DESC;

--  Q1. the business question,
--1. Question: Which staff members drive the most sales across all BikeStores locations?

--Q2. what the result measures, and
--2. Measures: The total number of completed orders and total net revenue generated per employee.

--Q3. why management should care about it.
--3. Value: Enables management to identify top talent for incentive programs and pinpoint underperformers who may need additional training. 

