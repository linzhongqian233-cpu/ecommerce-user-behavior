-- =============================================================
-- 00 一键执行全部分析（MySQL 版）
-- 用法：Ctrl+A 全选 → Alt+X 执行（不是 Ctrl+Enter）
-- 库：ecommerce   表：user_behavior（998 万行）
-- 预计耗时：约 5 分钟（其中 03 RFM 占 3.5 分钟）
-- =============================================================
USE ecommerce;


-- ############################################################
-- 来自 01_funnel.sql
-- ############################################################
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

-- ############################################################
-- 来自 02_cohort_retention.sql
-- ############################################################
-- =============================================================
-- 02 Cohort 留存  —— 【MySQL 版，打开即可运行】
-- 库：ecommerce   表：user_behavior（998 万行，10% 用户抽样）
--
-- 口径：以「首购日」分组，看第 N 天是否仍有任意行为
-- 关键：窗口只有 9 天，观测不足的 cohort 用 WHERE 排除，
--       而不是把「没观测到」算成 0（那会把留存算低一半）
-- =============================================================
-- ★ 执行方式：Ctrl+A 全选后按 Alt+X（整段逐条执行）；
--           Ctrl+Enter 只执行光标所在的一条，全选后按它会报 1064。

-- 2.1 整体留存（只统计观测窗口完整的 cohort：首购日 <= 2017-11-27）
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
WHERE first_dt <= '2017-11-27';

-- 2.2 分 cohort 明细（未观测满的格子显示 NULL，不填 0）
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

-- ############################################################
-- 来自 03_rfm.sql
-- ############################################################
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

-- ############################################################
-- 来自 04_anomaly.sql
-- ############################################################
-- =============================================================
-- 04 指标异常归因  —— 【MySQL 版，打开即可运行】
-- 库：ecommerce   表：user_behavior
--
-- 典型问题：「昨天转化率跌了 20%，怎么查？」
-- 排查顺序：先验数据 → 拆维度 → 看外部 → 定位环节
-- 本文件用真实数据把前两步跑一遍，后两步是方法论。
-- =============================================================
-- ★ 执行方式：Ctrl+A 全选后按 Alt+X（整段逐条执行）；
--           Ctrl+Enter 只执行光标所在的一条，全选后按它会报 1064。

-- 步骤 1：确认是不是真跌了（看趋势，别只看单点）
--           逐日转化率，一眼能看出哪天掉了
SELECT DATE(FROM_UNIXTIME(ts)) AS 日期,
       SUM(behavior = 'pv')    AS 浏览,
       SUM(behavior = 'cart')  AS 加购,
       SUM(behavior = 'buy')   AS 购买,
       ROUND(SUM(behavior = 'cart') * 100.0 / NULLIF(SUM(behavior = 'pv'), 0),   2) AS 浏览到加购率,
       ROUND(SUM(behavior = 'buy')  * 100.0 / NULLIF(SUM(behavior = 'cart'), 0), 2) AS 加购到购买率
FROM user_behavior
GROUP BY 日期
ORDER BY 日期;

-- 步骤 2：拆维度 —— 跌幅是某些品类拉下来的，还是全站一起跌？
--           若某个品类单独掉，指向该品类的商品/活动问题
SELECT category_id AS 品类,
       SUM(behavior = 'pv')   AS 浏览,
       SUM(behavior = 'cart') AS 加购,
       ROUND(SUM(behavior = 'cart') * 100.0 / NULLIF(SUM(behavior = 'pv'), 0), 2) AS 浏览到加购率
FROM user_behavior
GROUP BY category_id
HAVING SUM(behavior = 'pv') >= 5000
ORDER BY 浏览到加购率 ASC
LIMIT 15;

-- 步骤 3：拆品类 × 日期 —— 确认是"某品类某天突变"还是"长期偏低"
SELECT category_id AS 品类,
       DATE(FROM_UNIXTIME(ts)) AS 日期,
       SUM(behavior = 'pv')   AS 浏览,
       SUM(behavior = 'cart') AS 加购
FROM user_behavior
WHERE category_id IN (
    SELECT category_id FROM (
        SELECT category_id, SUM(behavior = 'pv') AS pv
        FROM user_behavior GROUP BY category_id
        HAVING pv >= 5000
        ORDER BY pv DESC LIMIT 3
    ) t
)
GROUP BY category_id, 日期
ORDER BY 品类, 日期;

-- =============================================================
-- 归因方法论（四步排查框架）
-- =============================================================
/*
1. 先验数据本身：埋点是否丢失？上报是否延迟？口径是否被改过？
   → 查总数是否突变、是否有大批 NULL/0 值
2. 再做维度下钻：版本 / 渠道 / 机型 / 地域 / 新老客 / 品类
   → 逐层 GROUP BY，看哪个切片的跌幅显著高于整体
3. 再看外部因素：节假日、竞品动作、舆情、政策、大促节奏
   → 和去年同期 / 上周同期对齐比较
4. 最后定位环节：把漏斗每一层单独看，找出是哪一环掉
   → 是「进入」掉了还是「转化」掉了，决定优化方向完全不同
*/
