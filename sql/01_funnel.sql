-- =============================================================
-- 01 转化漏斗  —— 【MySQL 版，打开即可运行】
-- 库：ecommerce   表：user_behavior（998 万行，10% 用户抽样）
--
-- 说明：文件末尾注释块保留了 DuckDB / PostgreSQL 语法版本。
--       两者差异：MySQL 不支持 COUNT(*) FILTER (WHERE ...)，
--                 需改用 SUM(condition)；时间转换用 FROM_UNIXTIME。
-- =============================================================
-- ★ 执行方式：Ctrl+A 全选后按 Alt+X（整段逐条执行）；
--           Ctrl+Enter 只执行光标所在的一条，全选后按它会报 1064。
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

-- =============================================================
-- 附：DuckDB / PostgreSQL 语法版本（仅作对照，MySQL 下不可执行）
-- =============================================================
/*
WITH stage AS (
    SELECT user_id,
           MAX(behavior = 'pv')   AS s_pv,
           MAX(behavior = 'fav')  AS s_fav,
           MAX(behavior = 'cart') AS s_cart,
           MAX(behavior = 'buy')  AS s_buy
    FROM user_behavior
    GROUP BY user_id
)
SELECT COUNT(*)                                    AS 总用户数,
       SUM(s_pv)                                   AS 浏览人数,
       SUM(s_cart)                                 AS 加购人数,
       SUM(s_buy)                                  AS 购买人数,
       ROUND(SUM(s_cart) / SUM(s_pv) * 100, 2)     AS 浏览到加购率,
       ROUND(SUM(s_buy)  / SUM(s_cart) * 100, 2)   AS 加购到购买率
FROM stage;
*/
