-- =============================================================
-- 01 转化漏斗（MySQL 8.0 版）
-- 库：ecommerce   表：user_behavior（10% 用户抽样，998 万行）
--
-- ⚠ 方言差异（和 DuckDB/PostgreSQL 版对比）：
--    MySQL 不支持 COUNT(*) FILTER (WHERE ...)
--      → 用 SUM(condition) 或 COUNT(CASE WHEN ... THEN 1 END)
--    MySQL 的 FROM_UNIXTIME 替代 to_timestamp
--    MySQL 的 DATEDIFF(a,b) 参数顺序是 (后, 前)
-- =============================================================
USE ecommerce;

-- 1.1 事件级漏斗（推荐口径：反映点击效率）
SELECT SUM(behavior = 'pv')   AS 浏览_pv,
       SUM(behavior = 'cart') AS 加购_cart,
       SUM(behavior = 'buy')  AS 购买_buy,
       ROUND(SUM(behavior = 'cart') * 100.0 / SUM(behavior = 'pv'),   2) AS 浏览到加购率,
       ROUND(SUM(behavior = 'buy')  * 100.0 / SUM(behavior = 'cart'), 2) AS 加购到购买率,
       ROUND(SUM(behavior = 'buy')  * 100.0 / SUM(behavior = 'pv'),   2) AS 整体转化率
FROM user_behavior;

-- 1.2 人级漏斗（9 天去重：反映人群覆盖，数值会显著高于事件级）
SELECT COUNT(DISTINCT CASE WHEN behavior = 'pv'   THEN user_id END) AS 浏览人数,
       COUNT(DISTINCT CASE WHEN behavior = 'fav'  THEN user_id END) AS 收藏人数,
       COUNT(DISTINCT CASE WHEN behavior = 'cart' THEN user_id END) AS 加购人数,
       COUNT(DISTINCT CASE WHEN behavior = 'buy'  THEN user_id END) AS 购买人数
FROM user_behavior;

-- 1.3 漏斗分品类下钻：找转化最差的品类
SELECT category_id AS 品类,
       SUM(behavior = 'pv')   AS 浏览,
       SUM(behavior = 'cart') AS 加购,
       SUM(behavior = 'buy')  AS 购买,
       ROUND(SUM(behavior = 'cart') * 100.0 / NULLIF(SUM(behavior = 'pv'), 0), 2) AS 浏览到加购率
FROM user_behavior
GROUP BY category_id
HAVING SUM(behavior = 'pv') >= 1000
ORDER BY 浏览到加购率 ASC
LIMIT 10;
