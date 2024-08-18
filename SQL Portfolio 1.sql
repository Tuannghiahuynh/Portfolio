SELECT TOP 500 *
FROM Orders

SELECT *
FROM Product

--Chuyển đổi dữ liệu cột Stock thành số
UPDATE Product
SET Stock = TRY_CONVERT(int, stock)

--Đưa dữ liệu kênh bán về cùng loại
UPDATE Orders SET Nguồn_đơn_hàng = 'Shopee' WHERE Nguồn_đơn_hàng = 'Shopee 84' --Thay nguồn đơn hàng tên là Shopee 84 thành Shopee
UPDATE Orders SET Nguồn_đơn_hàng = 'Tiktok' WHERE Nguồn_đơn_hàng = 'Tiktok 84' --Thay nguồn đơn hàng tên là Tiktok 84 thành Tiktok;

--Lọc giá trị đơn hàng bị trùng
WITH CTE AS
(
SELECT *,
	ROW_NUMBER() OVER(
	PARTITION BY ID_đơn_hàng 
				 ORDER BY Mã_vạch) AS RowNumber
FROM Portfolio.dbo.Orders
)
UPDATE CTE SET Giá_trị_đơn_hàng = 0 WHERE RowNumber > 1;

--Thêm cột Chiết khấu cho từng đơn hàng
ALTER TABLE Orders
ADD Chiết_khấu int;

--Sử dụng CTE để tính tổng chiết khấu cho mỗi đơn hàng
WITH Ordertotal AS
(
SELECT ID_đơn_hàng,
	   CAST((((Sum(CAST(Giá * Số_lượng AS Decimal)) - Sum(CAST(Giá_trị_đơn_hàng AS Decimal))) / Sum(CAST(Giá * Số_lượng AS Decimal))) * 100) AS Decimal(10,2)) AS CK
FROM Orders
GROUP BY ID_đơn_hàng
)
--SELECT ID_đơn_hàng,
--		 CK
--FROM Ordertotal
UPDATE Orders
SET Orders.Chiết_khấu = Ordertotal.CK
FROM Orders
INNER JOIN Ordertotal
ON Orders.ID_đơn_hàng = Ordertotal.ID_đơn_hàng;

--Doanh thu, chiết khấu theo kênh bán, thời gian
SELECT Month(Thời_gian) AS Tháng,
	   Sum(Cast(Giá_trị_đơn_hàng AS bigint)) AS Tổng_doanh_thu,
	   AVG(Chiết_khấu) AS Chiết_khấu_TB,
	   Nguồn_đơn_hàng
FROM Orders
WHERE Trạng_thái = 'Thành công'
GROUP BY Month(Thời_gian), Nguồn_đơn_hàng
ORDER BY Month(Thời_gian), Nguồn_đơn_hàng;

--Tính Month-on-hand (MOH) = Tồn kho / Số bán trung bình theo Product_group
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
           WHEN Sum(O.Số_lượng) > 0 THEN CAST(S.Tồn AS float) / (Sum(O.Số_lượng) / 3)
           ELSE NULL
       END AS MOH
FROM StockSummary S
JOIN Product P 
 ON S.Product_group = P.Product_group
LEFT JOIN Orders O 
 ON P.Mã_vạch = O.mã_vạch
GROUP BY P.Product_group, S.Tồn;

--TOP 5 SP bán chạy từng tháng
WITH MonthlySales AS
(
SELECT Mã_vạch,
	   Sản_phẩm,
	   Sum(Số_lượng) AS Số_bán,
	   Month(Thời_gian) AS Tháng,
	   ROW_NUMBER () OVER (PARTITION BY Month(Thời_gian)
						   ORDER BY Sum(Số_lượng) DESC) AS Rank
FROM Orders
GROUP BY Sản_phẩm, Mã_vạch, Month(Thời_gian)
)
SELECT *
FROM MonthlySales
WHERE Rank <= 5
ORDER BY Tháng, Rank;

--Tồn kho tháng 9, 10, 11
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
	   Sum(Cast(p.Stock AS int)) - Coalesce(Sum(cs.Sales_thang11), 0) AS Stock_end_thang10,
	   Sum(Cast(p.Stock AS int)) - Coalesce(Sum(cs.Sales_thang10), 0) AS Stock_end_thang9,
	   Sum(Cast(p.Stock AS int)) - Coalesce(Sum(cs.Sales_thang9), 0) AS Stock_end_thang8
FROM Product p
LEFT JOIN CumulativeSales cs ON p.Tên_sản_phẩm = cs.Sản_phẩm
GROUP BY p.Product_group
ORDER BY p.Product_group;

--Số bán tháng 9, 10, 11
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