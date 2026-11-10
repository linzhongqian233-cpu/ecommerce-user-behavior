-- =============================================================
-- 04 指标异常归因  —— 【MySQL 版，打开即可运行】
-- 库：ecommerce   表：user_behavior
--
-- 面试高频题：「昨天转化率跌了 20%，怎么查？」
-- 排查顺序：先验数据 → 拆维度 → 看外部 → 定位环节
-- 本文件用真实数据把前两步跑一遍，后两步是方法论。
-- =============================================================
-- ★ 执行方式：Ctrl+A 全选后按 Alt+X（整段逐条执行）；
--           Ctrl+Enter 只执行光标所在的一条，全选后按它会报 1064。
USE ecommerce;

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
-- 归因方法论（面试可直接背）
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
