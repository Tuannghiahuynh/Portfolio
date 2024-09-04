SELECT TOP 500 *
FROM Orders

SELECT *
FROM Product

--Chuyển đổi dữ liệu cột Stock thành số
UPDATE Product
SET Stock = TRY_CONVERT(int, stock)

--Get sales channel data into the right format
UPDATE Orders SET Nguồn_đơn_hàng = 'Shopee' WHERE Nguồn_đơn_hàng = 'Shopee 84' --Change the order source name from Shopee 84 to Shopee
UPDATE Orders SET Nguồn_đơn_hàng = 'Tiktok' WHERE Nguồn_đơn_hàng = 'Tiktok 84'; --Change the order source name from Tiktok 84 to Tiktok

--Filter duplicate order values
WITH CTE AS
(
SELECT *,
	ROW_NUMBER() OVER( PARTITION BY ID_đơn_hàng --Use partition by Order_ID to filter duplicate Order 
					   ORDER BY Mã_vạch) AS RowNumber
FROM Portfolio.dbo.Orders
)
UPDATE CTE SET Giá_trị_đơn_hàng = 0 WHERE RowNumber > 1; --Update duplicate Order_ID column with number 0

--Add Discount column for each order
ALTER TABLE Orders
ADD Chiết_khấu int;

--Use CTE to calculate total discount for each order
WITH Ordertotal AS
(
SELECT ID_đơn_hàng,
	   CAST((((Sum(CAST(Giá * Số_lượng AS Decimal)) - Sum(CAST(Giá_trị_đơn_hàng AS Decimal))) / Sum(CAST(Giá * Số_lượng AS Decimal))) * 100) AS Decimal(10,2)) AS Discount --Calculate discount for each items sold
FROM Orders
GROUP BY ID_đơn_hàng
)
--SELECT ID_đơn_hàng,
--		 Discount
--FROM Ordertotal
UPDATE Orders
SET Orders.Chiết_khấu = Ordertotal.Discount
FROM Orders
INNER JOIN Ordertotal
ON Orders.ID_đơn_hàng = Ordertotal.ID_đơn_hàng;

--Revenue, discounts by sales channel, time
SELECT Month(Thời_gian) AS Tháng,
	   Sum(Cast(Giá_trị_đơn_hàng AS bigint)) AS Tổng_doanh_thu,
	   AVG(Chiết_khấu) AS Chiết_khấu_TB,
	   Nguồn_đơn_hàng
FROM Orders
WHERE Trạng_thái = 'Thành công'
GROUP BY Month(Thời_gian), Nguồn_đơn_hàng
ORDER BY Month(Thời_gian), Nguồn_đơn_hàng;

--Calculate Month-on-hand (MOH) = Inventory / Average Sales by Product_group
WITH StockSummary AS
(
SELECT Sum(Cast(stock as int)) AS Tồn,
	   Product_group
FROM Product
GROUP BY Product_group
)
SELECT S.Tồn, P.Product_group,
       Sum(O.Số_lượng) / 3 AS Bán,
       CASE 
           WHEN Sum(O.Số_lượng) > 0 THEN CAST(S.Tồn AS float) / (Sum(O.Số_lượng) / 3) --Calculate Month-on-hand
           ELSE NULL
       END AS MOH
FROM StockSummary S
JOIN Product P 
 ON S.Product_group = P.Product_group
LEFT JOIN Orders O 
 ON P.Mã_vạch = O.mã_vạch
GROUP BY P.Product_group, S.Tồn;

--TOP 5 best-selling products every month
WITH MonthlySales AS
(
SELECT Mã_vạch,
	   Sản_phẩm,
	   Sum(Số_lượng) AS Số_bán,
	   Month(Thời_gian) AS Tháng,
	   ROW_NUMBER () OVER (PARTITION BY Month(Thời_gian)
						   ORDER BY Sum(Số_lượng) DESC) AS Rank --Rank top-selling items by Month
FROM Orders
GROUP BY Sản_phẩm, Mã_vạch, Month(Thời_gian)
)
SELECT *
FROM MonthlySales
WHERE Rank <= 5
ORDER BY Tháng, Rank;

--Inventory September, October, November
WITH CumulativeSales AS
(
SELECT O.Sản_phẩm,
	   Sum(CASE WHEN Month(Thời_gian) = 11 THEN o.Số_lượng ELSE 0 END) AS Sales_Thang11,
	   Sum(CASE WHEN Month(Thời_gian) IN (11, 10) THEN o.Số_lượng ELSE 0 END) AS Sales_Thang10,
	   Sum(CASE WHEN Month(Thời_gian) IN (11, 10, 9) THEN o.Số_lượng ELSE 0 END) AS Sales_Thang9
FROM Orders o
GROUP BY Sản_phẩm
)
SELECT p.Product_group,
	   Sum(Cast(p.Stock AS int)) AS Current_stock,
	   Sum(Cast(p.Stock AS int)) - Coalesce(Sum(cs.Sales_thang11), 0) AS Stock_end_thang10, --Use coalesce to calculate the ending inventory of each month
	   Sum(Cast(p.Stock AS int)) - Coalesce(Sum(cs.Sales_thang10), 0) AS Stock_end_thang9, --Ex: beginning inventory of November is 15, 3 were sold in October, so the ending inventory at September is 12
	   Sum(Cast(p.Stock AS int)) - Coalesce(Sum(cs.Sales_thang9), 0) AS Stock_end_thang8
FROM Product p
LEFT JOIN CumulativeSales cs ON p.Tên_sản_phẩm = cs.Sản_phẩm
GROUP BY p.Product_group
ORDER BY p.Product_group;

--Sales for September, October, November
WITH SalesMonthly AS
(
SELECT p.Product_group,
	   Sum(o.Số_lượng) AS Số_bán,
	   Month(o.Thời_gian) AS Tháng
FROM Orders o
LEFT JOIN Product p ON o.Mã_vạch = p.Mã_vạch
GROUP BY Month(o.Thời_gian), p.Product_group
)
SELECT *
FROM SalesMonthly sm
WHERE Product_group IS NOT NULL
ORDER BY sm.Tháng
