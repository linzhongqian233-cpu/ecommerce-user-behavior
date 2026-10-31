-- =============================================================
-- 02 Cohort 留存（MySQL 8.0 版）
-- 库：ecommerce   表：user_behavior（10% 用户抽样，998 万行）
--
-- 口径：以「首购日」分组，看第 N 天是否仍有任意行为
-- 说明：窗口仅 9 天，30 日留存无法计算；末尾 cohort 观测不足，
--       用 WHERE 限制 cohort 日期，而不是把未观测到算成 0
-- =============================================================
USE ecommerce;

-- 2.1 整体留存（只统计观测窗口完整的 cohort：首购日 <= 2017-11-30）
WITH fb AS (
    SELECT user_id, MIN(DATE(FROM_UNIXTIME(ts))) AS first_dt
    FROM user_behavior
    WHERE behavior = 'buy'
    GROUP BY user_id
),
act AS (
    SELECT DISTINCT user_id, DATE(FROM_UNIXTIME(ts)) AS act_dt
    FROM user_behavior
),
rel AS (
    SELECT fb.user_id, fb.first_dt, DATEDIFF(act.act_dt, fb.first_dt) AS day_n
    FROM fb JOIN act USING (user_id)
)
SELECT COUNT(DISTINCT user_id) AS 首购用户,
       ROUND(COUNT(DISTINCT CASE WHEN day_n = 1 THEN user_id END) * 100.0
             / COUNT(DISTINCT user_id), 1) AS 次日留存率,
       ROUND(COUNT(DISTINCT CASE WHEN day_n = 3 THEN user_id END) * 100.0
             / COUNT(DISTINCT user_id), 1) AS 第3日留存率,
       ROUND(COUNT(DISTINCT CASE WHEN day_n = 7 THEN user_id END) * 100.0
             / COUNT(DISTINCT user_id), 1) AS 第7日留存率
FROM rel
WHERE first_dt <= '2017-11-27';   -- 只有这之前的 cohort 才观测满 7 天

-- 2.2 分 cohort 明细（未观测满的格子留 NULL，不填 0）
WITH fb AS (
    SELECT user_id, MIN(DATE(FROM_UNIXTIME(ts))) AS first_dt
    FROM user_behavior WHERE behavior = 'buy' GROUP BY user_id
),
act AS (
    SELECT DISTINCT user_id, DATE(FROM_UNIXTIME(ts)) AS act_dt FROM user_behavior
),
rel AS (
    SELECT fb.user_id, fb.first_dt, DATEDIFF(act.act_dt, fb.first_dt) AS day_n
    FROM fb JOIN act USING (user_id)
),
base AS (
    SELECT first_dt, COUNT(DISTINCT user_id) AS 新增用户 FROM fb GROUP BY first_dt
),
agg AS (
    SELECT first_dt,
           COUNT(DISTINCT CASE WHEN day_n = 1 THEN user_id END) AS d1,
           COUNT(DISTINCT CASE WHEN day_n = 3 THEN user_id END) AS d3
    FROM rel GROUP BY first_dt
)
SELECT b.first_dt AS 首购日,
       b.新增用户,
       CASE WHEN b.first_dt <= '2017-12-02' THEN ROUND(a.d1 * 100.0 / b.新增用户, 1) END AS 次日留存率,
       CASE WHEN b.first_dt <= '2017-11-30' THEN ROUND(a.d3 * 100.0 / b.新增用户, 1) END AS 第3日留存率
FROM base b JOIN agg a USING (first_dt)
ORDER BY b.first_dt;
