-- =============================================================
-- 04 指标异常归因（面试高频：「昨天转化率跌了 20%，怎么查」）
-- 排查顺序：先验数据 → 拆维度 → 看外部 → 定位环节
-- =============================================================

-- -------------------------------------------------------------
-- B. 练手版：school_db（及格率异常归因）
-- -------------------------------------------------------------
USE school_db;

-- 步骤 1：确认是不是真跌了（看趋势，而不是只看单点）
SELECT term AS 学期,
       COUNT(*)                                        AS 人次,
       ROUND(AVG(score), 2)                            AS 平均分,
       ROUND(SUM(score >= 60) / COUNT(*) * 100, 2)     AS 及格率
FROM enrollment
WHERE score IS NOT NULL
GROUP BY term
ORDER BY term;

-- 步骤 2：拆维度 —— 是哪些院系拖下来的？
SELECT term AS 学期, d.dept_name AS 院系,
       ROUND(SUM(e.score >= 60) / COUNT(*) * 100, 2) AS 及格率,
       COUNT(*) AS 人次
FROM enrollment e
JOIN course co ON e.course_id = co.course_id
JOIN dept   d  ON co.dept_id  = d.dept_id
WHERE e.score IS NOT NULL
GROUP BY term, d.dept_name
ORDER BY 学期, 及格率 ASC;

-- 步骤 3：继续拆 —— 是某门课的问题（课程难度突增？换老师？）
SELECT co.course_name AS 课程, co.course_type AS 类型,
       COUNT(*) AS 人次,
       ROUND(AVG(e.score), 2) AS 平均分,
       ROUND(SUM(e.score < 60) / COUNT(*) * 100, 1) AS 不及格率
FROM enrollment e
JOIN course co ON e.course_id = co.course_id
WHERE e.score IS NOT NULL
GROUP BY co.course_id, co.course_name, co.course_type
HAVING COUNT(*) >= 100
ORDER BY 不及格率 DESC
LIMIT 15;

-- 步骤 4：换老师有没有影响（同课不同师对比）
SELECT co.course_name AS 课程, t.teacher_id,
       COUNT(*) AS 人次, ROUND(AVG(e.score), 2) AS 平均分
FROM enrollment e
JOIN course co   ON e.course_id  = co.course_id
JOIN teaching tg ON tg.course_id = e.course_id AND tg.class_id = e.class_id
JOIN teacher t   ON t.teacher_id = tg.teacher_id
WHERE e.score IS NOT NULL
GROUP BY co.course_name, t.teacher_id
HAVING COUNT(*) >= 40
ORDER BY co.course_name, 平均分 DESC;

-- 步骤 5：异常时段（有没有某个学期整体偏高/偏低 = 评分口径变了）
SELECT term AS 学期, COUNT(DISTINCT course_id) AS 开课门数,
       ROUND(AVG(score), 2) AS 平均分,
       MIN(score) AS 最低, MAX(score) AS 最高
FROM enrollment
WHERE score IS NOT NULL
GROUP BY term
ORDER BY term;

-- -------------------------------------------------------------
-- 归因模板（面试可直接背）
-- -------------------------------------------------------------
/*
1. 先验数据本身：埋点是否丢失？上报是否有延迟？口径是否被改过？
   → 查总数是否突变、查是否有大批 NULL/0 值
2. 再做维度下钻：版本 / 渠道 / 机型 / 地域 / 新老客 / 品类
   → 逐层 GROUP BY，看哪个切片的跌幅显著高于整体
3. 再看外部因素：节假日、竞品动作、舆情、政策、大促节奏
   → 和去年同期 / 上周同期对齐比较
4. 最后定位环节：把漏斗每一层的转化率单独看，找出是哪一环掉
   → 是「进入」掉了还是「转化」掉了，决定优化方向完全不同
*/
