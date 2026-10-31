-- =============================================================
-- 01 转化漏斗
-- 口径：按「人」去重，不是按「次」。分母 = 上一环节的人数。
-- 两层写法：CTE 先出明细，外层再算比率（避免窗口函数与聚合混算）
-- =============================================================

-- -------------------------------------------------------------
-- A. 正式版：UserBehavior（淘宝行为日志）
--    前提：已建表 user_behavior(user_id,item_id,category_id,behavior,ts)
-- -------------------------------------------------------------
/*
WITH stage AS (
    SELECT user_id,
           MAX(behavior = 'pv')   AS s_pv,
           MAX(behavior = 'fav')  AS s_fav,
           MAX(behavior = 'cart') AS s_cart,
           MAX(behavior = 'buy')  AS s_buy
    FROM user_behavior
    WHERE ts >= UNIX_TIMESTAMP('2017-11-25')
      AND ts <  UNIX_TIMESTAMP('2017-12-04')
    GROUP BY user_id
)
SELECT COUNT(*)                                        AS 总用户数,
       SUM(s_pv)                                       AS 浏览人数,
       SUM(s_fav)                                      AS 收藏人数,
       SUM(s_cart)                                     AS 加购人数,
       SUM(s_buy)                                      AS 购买人数,
       ROUND(SUM(s_cart) / SUM(s_pv) * 100, 2)         AS 浏览到加购率,
       ROUND(SUM(s_fav)  / SUM(s_cart) * 100, 2)       AS 加购到收藏率,
       ROUND(SUM(s_buy)  / SUM(s_cart) * 100, 2)       AS 加购到购买率,
       ROUND(SUM(s_buy)  / SUM(s_pv) * 100, 2)         AS 整体转化率
FROM stage;
*/

-- 分品类看漏斗（找转化率最差的品类）
/*
SELECT category_id AS 品类,
       COUNT(*)                                              AS 总用户,
       ROUND(SUM(s_buy) / SUM(s_pv) * 100, 2)                AS 浏览到购买率,
       ROUND(SUM(s_cart) / SUM(s_pv) * 100, 2)               AS 浏览到加购率,
       ROUND(SUM(s_buy) / NULLIF(SUM(s_cart), 0) * 100, 2)   AS 加购到购买率
FROM (
    SELECT user_id, category_id,
           MAX(behavior = 'pv')   AS s_pv,
           MAX(behavior = 'cart') AS s_cart,
           MAX(behavior = 'buy')  AS s_buy
    FROM user_behavior
    GROUP BY user_id, category_id
) t
GROUP BY category_id
HAVING COUNT(*) >= 50
ORDER BY 浏览到购买率 ASC
LIMIT 20;
*/

-- -------------------------------------------------------------
-- B. 练手版：school_db（现在就能跑）
--    等价漏斗：选课 → 出成绩 → 及格 → 优秀
-- -------------------------------------------------------------
USE school_db;

-- B1. 整体四层漏斗
SELECT COUNT(*)                              AS 选课人次,
       SUM(score IS NOT NULL)                AS 出分人次,
       SUM(score >= 60)                      AS 及格人次,
       SUM(score >= 90)                      AS 优秀人次,
       ROUND(SUM(score IS NOT NULL) / COUNT(*) * 100, 2)  AS 出分率,
       ROUND(SUM(score >= 60) / COUNT(*) * 100, 2)        AS 及格率,
       ROUND(SUM(score >= 90) / COUNT(*) * 100, 2)        AS 优秀率
FROM enrollment;

-- B2. 分维度下钻：哪个院系的及格率最低？
SELECT d.dept_name AS 院系,
       COUNT(*)                                          AS 选课人次,
       ROUND(SUM(e.score >= 60) / COUNT(*) * 100, 2)     AS 及格率,
       ROUND(SUM(e.score >= 90) / COUNT(*) * 100, 2)     AS 优秀率,
       ROUND(AVG(CASE WHEN e.score IS NOT NULL THEN e.score END), 2) AS 平均分
FROM enrollment e
JOIN course co ON e.course_id = co.course_id
JOIN dept   d  ON co.dept_id  = d.dept_id
GROUP BY d.dept_name
ORDER BY 及格率 ASC;

-- B3. 漏斗按课程类型拆（必修 vs 选修 vs 实践）
SELECT co.course_type AS 课程类型,
       COUNT(*)                                          AS 选课人次,
       ROUND(SUM(e.score >= 60) / COUNT(*) * 100, 2)     AS 及格率
FROM enrollment e
JOIN course co ON e.course_id = co.course_id
GROUP BY co.course_type
ORDER BY 及格率 DESC;
