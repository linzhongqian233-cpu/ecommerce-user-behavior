-- =============================================================
-- 03 RFM 用户分层
-- R 最近一次消费、F 消费频次、M 消费金额（此处用学分/门数替代）
-- 方法：NTILE(4) 四等分打分，再组合成 8 类人群
-- 注意：R 越小越好，所以打分要反向
-- =============================================================

-- -------------------------------------------------------------
-- A. 正式版：UserBehavior（无金额，用行为量与天数替代）
-- -------------------------------------------------------------
/*
WITH base AS (
    SELECT user_id,
           DATEDIFF('2017-12-03', MAX(DATE(FROM_UNIXTIME(ts))))    AS recency,
           COUNT(*)                                                AS frequency,
           SUM(behavior = 'buy')                                   AS buy_cnt,
           COUNT(DISTINCT item_id)                                 AS distinct_items
    FROM user_behavior
    GROUP BY user_id
),
scored AS (
    SELECT *,
           NTILE(4) OVER (ORDER BY recency DESC)          AS r_score,  -- 越近分越高
           NTILE(4) OVER (ORDER BY frequency ASC)         AS f_score,
           NTILE(4) OVER (ORDER BY distinct_items ASC)    AS m_score
    FROM base
)
SELECT CASE
         WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN '重要价值用户'
         WHEN r_score >= 3 AND f_score <  3 AND m_score >= 3 THEN '重要发展用户'
         WHEN r_score <  3 AND f_score >= 3 AND m_score >= 3 THEN '重要保持用户'
         WHEN r_score <  3 AND f_score <  3 AND m_score >= 3 THEN '重要挽留用户'
         WHEN r_score >= 3 AND f_score >= 3 AND m_score <  3 THEN '一般价值用户'
         WHEN r_score >= 3 AND f_score <  3 AND m_score <  3 THEN '新用户'
         WHEN r_score <  3 AND f_score >= 3 AND m_score <  3 THEN '一般保持用户'
         ELSE '流失用户'
       END AS 用户分层,
       COUNT(*)                AS 人数,
       ROUND(AVG(recency), 1)  AS 平均最近间隔天数,
       ROUND(AVG(frequency),1) AS 平均行为次数
FROM scored
GROUP BY 用户分层
ORDER BY 人数 DESC;
*/

-- -------------------------------------------------------------
-- B. 练手版：school_db（学生活跃度分层）
--    R = 最近选课学期、F = 选课门数、M = 修得总学分
-- -------------------------------------------------------------
USE school_db;

WITH base AS (
    SELECT s.student_id,
           s.student_no,
           s.name,
           MAX(e.term)                                  AS 最近学期,
           COUNT(*)                                     AS 选课门数,
           SUM(co.credit)                               AS 总学分,
           ROUND(AVG(e.score), 2)                       AS 平均分
    FROM student s
    JOIN enrollment e ON s.student_id = e.student_id
    JOIN course co    ON e.course_id  = co.course_id
    WHERE e.score IS NOT NULL
    GROUP BY s.student_id, s.student_no, s.name
),
scored AS (
    SELECT *,
           NTILE(4) OVER (ORDER BY 最近学期 DESC)  AS r_score,
           NTILE(4) OVER (ORDER BY 选课门数 ASC)   AS f_score,
           NTILE(4) OVER (ORDER BY 总学分 ASC)     AS m_score
    FROM base
)
SELECT CASE
         WHEN r_score = 4 AND f_score = 4 THEN '高价值活跃'
         WHEN r_score = 4 AND f_score <= 3 THEN '新晋用户'
         WHEN r_score <= 3 AND f_score = 4 THEN '高价值沉睡'
         WHEN r_score = 1 AND f_score = 1 THEN '流失风险'
         ELSE '一般用户'
       END                              AS 学生分层,
       COUNT(*)                         AS 人数,
       ROUND(AVG(选课门数), 1)          AS 平均选课门数,
       ROUND(AVG(总学分), 1)            AS 平均学分,
       ROUND(AVG(平均分), 2)            AS 平均成绩
FROM scored
GROUP BY 学生分层
ORDER BY 人数 DESC;

-- 明细：拿分层结果直接产出运营名单（这一步才是业务价值）
WITH base AS (
    SELECT s.student_id, s.student_no, s.name, MAX(e.term) AS 最近学期,
           COUNT(*) AS 选课门数, SUM(co.credit) AS 总学分
    FROM student s
    JOIN enrollment e ON s.student_id = e.student_id
    JOIN course co    ON e.course_id  = co.course_id
    WHERE e.score IS NOT NULL
    GROUP BY s.student_id, s.student_no, s.name
)
SELECT student_no AS 学号, name AS 姓名, 最近学期, 选课门数, 总学分
FROM base
WHERE 最近学期 < '2023-2024-1'
ORDER BY 总学分 DESC
LIMIT 50;
