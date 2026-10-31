-- =============================================================
-- 02 留存分析（Cohort 同期群）
-- 口径：按「首次行为日」分组，看后续第 N 天是否仍有行为。
-- 关键点：用 ROW_NUMBER / DATEDIFF 算「相对第几天」，不是自然日。
-- =============================================================

-- -------------------------------------------------------------
-- A. 正式版：UserBehavior（首购留存）
-- -------------------------------------------------------------
/*
WITH first_buy AS (
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
    SELECT f.user_id, f.first_dt,
           DATEDIFF(a.act_dt, f.first_dt) AS day_n
    FROM first_buy f
    JOIN act a ON f.user_id = a.user_id
)
SELECT first_dt AS 首购日,
       COUNT(DISTINCT user_id)                                        AS 新增用户,
       COUNT(DISTINCT CASE WHEN day_n = 1  THEN user_id END)          AS 次日留存,
       COUNT(DISTINCT CASE WHEN day_n = 7  THEN user_id END)          AS 7日留存,
       COUNT(DISTINCT CASE WHEN day_n = 30 THEN user_id END)          AS 30日留存,
       ROUND(COUNT(DISTINCT CASE WHEN day_n = 1 THEN user_id END)
             / COUNT(DISTINCT user_id) * 100, 2)                      AS 次日留存率
FROM rel
GROUP BY first_dt
ORDER BY first_dt;
*/

-- 留存热力图矩阵（首购日 × 第 N 天），直接喂给 BI 做热力图
/*
WITH first_buy AS (
    SELECT user_id, MIN(DATE(FROM_UNIXTIME(ts))) AS first_dt
    FROM user_behavior WHERE behavior = 'buy' GROUP BY user_id
),
rel AS (
    SELECT f.user_id, f.first_dt,
           DATEDIFF(DATE(FROM_UNIXTIME(a.ts)), f.first_dt) AS day_n
    FROM first_buy f
    JOIN user_behavior a ON f.user_id = a.user_id
)
SELECT first_dt AS 首购日, day_n AS 第N天, COUNT(DISTINCT user_id) AS 留存人数
FROM rel
WHERE day_n BETWEEN 0 AND 30
GROUP BY first_dt, day_n
ORDER BY first_dt, day_n;
*/

-- -------------------------------------------------------------
-- B. 练手版：school_db
--    学期留存：每个学生从入学起，第几个学期还在选课
-- -------------------------------------------------------------
USE school_db;

-- B1. 按入学年份的学期留存矩阵
WITH cohort AS (
    SELECT s.student_id, c.enroll_year AS 入学年份
    FROM student s
    JOIN class c ON s.class_id = c.class_id
),
term_act AS (
    SELECT student_id, term,
           ROW_NUMBER() OVER (PARTITION BY student_id ORDER BY term) AS 期序
    FROM (SELECT DISTINCT student_id, term FROM enrollment) d
)
SELECT co.入学年份,
       COUNT(DISTINCT CASE WHEN t.期序 = 1 THEN t.student_id END) AS 第1学期,
       COUNT(DISTINCT CASE WHEN t.期序 = 2 THEN t.student_id END) AS 第2学期,
       COUNT(DISTINCT CASE WHEN t.期序 = 3 THEN t.student_id END) AS 第3学期,
       COUNT(DISTINCT CASE WHEN t.期序 = 4 THEN t.student_id END) AS 第4学期
FROM cohort co
JOIN term_act t ON co.student_id = t.student_id
GROUP BY co.入学年份
ORDER BY co.入学年份;

-- B2. 长表版（喂给 BI 画热力图）
WITH term_act AS (
    SELECT student_id, term,
           ROW_NUMBER() OVER (PARTITION BY student_id ORDER BY term) AS 期序
    FROM (SELECT DISTINCT student_id, term FROM enrollment) d
)
SELECT 期序 AS 第N学期, COUNT(DISTINCT student_id) AS 留存人数
FROM term_act
GROUP BY 期序
ORDER BY 期序;

-- B3. 留存率而非绝对人数（分母固定为第 1 学期人数）
-- ⚠ 坑：不要写成「CROSS JOIN 一个单行 CTE」，
--        MySQL 8.0.21 的优化器在这个模式下会让 mysqld 直接崩溃（实测踩过）。
--        改成标量子查询，结果一样且稳定。
WITH term_act AS (
    SELECT student_id, term,
           ROW_NUMBER() OVER (PARTITION BY student_id ORDER BY term) AS 期序
    FROM (SELECT DISTINCT student_id, term FROM enrollment) d
),
agg AS (
    SELECT 期序, COUNT(DISTINCT student_id) AS 人数
    FROM term_act
    GROUP BY 期序
)
SELECT 期序 AS 第N学期,
       人数,
       ROUND(人数 / (SELECT 人数 FROM agg WHERE 期序 = 1) * 100, 2) AS 留存率
FROM agg
ORDER BY 第N学期;
