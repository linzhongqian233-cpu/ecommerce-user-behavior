-- =============================================================
-- 03 RFM 用户分层  —— 【MySQL 版，打开即可运行】
-- 库：ecommerce   表：user_behavior（998 万行，10% 用户抽样）
--
-- ⚠ 关键坑：R 若用「距最后一次任意行为」定义会失效
--   （9 天窗口 + 高频用户 → 全员 R≈0，分层只剩 F 在起作用）。
--   必须改成「距最后一次购买的天数」，并把零购买用户单列。
--
-- 性能提示：本文件在 MySQL 8.0.21 上约需 4 分钟（CTE 物化 + 窗口排序）。
--   若只想看分层结果，先只跑 3.1；3.2 的名单查询最慢，可单独跑。
-- =============================================================
-- ★ 执行方式：Ctrl+A 全选后按 Alt+X（整段逐条执行）；
--           Ctrl+Enter 只执行光标所在的一条，全选后按它会报 1064。
USE ecommerce;

-- 3.1 分层汇总
WITH u AS (
    SELECT user_id,
           COUNT(*)                AS freq,
           SUM(behavior = 'buy')   AS buy_cnt,
           COUNT(DISTINCT item_id) AS item_cnt,
           CASE WHEN SUM(behavior = 'buy') = 0 THEN NULL
                ELSE DATEDIFF('2017-12-03',
                       MAX(CASE WHEN behavior = 'buy' THEN DATE(FROM_UNIXTIME(ts)) END))
           END                     AS r_buy_days
    FROM user_behavior
    GROUP BY user_id
),
scored AS (
    SELECT *,
           6 - NTILE(4) OVER (PARTITION BY (buy_cnt = 0) ORDER BY COALESCE(r_buy_days, 0) ASC) AS r_score,
           NTILE(4)     OVER (PARTITION BY (buy_cnt = 0) ORDER BY freq ASC)                     AS f_score
    FROM u
),
seg AS (
    SELECT *,
           CASE WHEN buy_cnt = 0 THEN 'P 未购买用户'
                WHEN r_score >= 4 AND f_score >= 4 THEN '01 重要价值'
                WHEN r_score >= 4 AND f_score <  4 THEN '02 新晋高潜'
                WHEN r_score <  4 AND f_score >= 4 THEN '03 沉睡高价值'
                ELSE '04 流失风险' END AS 分层
    FROM scored
)
SELECT 分层,
       COUNT(*)                                           AS 人数,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS 占比,
       ROUND(AVG(freq), 0)                                AS 平均行为次数,
       ROUND(AVG(buy_cnt), 2)                             AS 平均购买次数,
       ROUND(AVG(item_cnt), 0)                            AS 平均商品数
FROM seg
GROUP BY 分层
ORDER BY 分层;

-- 3.2 运营名单：未购买但行为频繁的用户（可直接交给运营发券）
WITH u AS (
    SELECT user_id,
           COUNT(*)              AS freq,
           SUM(behavior = 'buy') AS buy_cnt,
           COUNT(DISTINCT item_id) AS item_cnt
    FROM user_behavior
    GROUP BY user_id
)
SELECT user_id, freq, item_cnt
FROM u
WHERE buy_cnt = 0 AND freq >= 100
ORDER BY freq DESC
LIMIT 100;
