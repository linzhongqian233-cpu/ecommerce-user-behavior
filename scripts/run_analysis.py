# -*- coding: utf-8 -*-
"""全流程分析：漏斗 / Cohort 留存 / RFM 分层

产出：
    reports/01_funnel_event_level.png
    reports/02_cohort_d1_retention.png
    reports/04_rfm_segments.png
    reports/tables/*.csv
"""
import duckdb
import os
import sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import WINDOW, REPORTS, TABLES

plt.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei"]
plt.rcParams["axes.unicode_minus"] = False
os.makedirs(REPORTS, exist_ok=True)
os.makedirs(TABLES, exist_ok=True)


def q(sql):
    return duckdb.sql(sql).df()


# ---------------- 1. 漏斗 ----------------
print("=" * 70)
print("【1】转化漏斗")
print("=" * 70)
ev = q(f"""
SELECT SUM(behavior='pv')   AS pv,
       SUM(behavior='fav')  AS fav,
       SUM(behavior='cart') AS cart,
       SUM(behavior='buy')  AS buy
FROM {WINDOW}
""").iloc[0]

fp = q(f"""
SELECT COUNT(DISTINCT CASE WHEN behavior='pv'   THEN user_id END) AS pv,
       COUNT(DISTINCT CASE WHEN behavior='cart' THEN user_id END) AS cart,
       COUNT(DISTINCT CASE WHEN behavior='buy'  THEN user_id END) AS buy
FROM {WINDOW}
""").iloc[0]

print(f"事件级：pv {ev.pv:,.0f} → cart {ev.cart:,.0f} ({ev.cart/ev.pv*100:.2f}%) "
      f"→ buy {ev.buy:,.0f} ({ev.buy/ev.cart*100:.2f}%)，整体 {ev.buy/ev.pv*100:.2f}%")
print(f"人级：  浏览 {fp.pv:,.0f} → 加购 {fp.cart:,.0f} ({fp.cart/fp.pv*100:.2f}%) "
      f"→ 购买 {fp.buy:,.0f} ({fp.buy/fp.cart*100:.2f}%)")

ev.to_frame().T.to_csv(os.path.join(TABLES, "funnel_event_level.csv"),
                       index=False, encoding="utf-8-sig")

fig, ax = plt.subplots(figsize=(10, 5))
stages = ["浏览 pv", "加购 cart", "购买 buy"]
vals = [ev.pv, ev.cart, ev.buy]
ax.barh(stages[::-1], vals[::-1], color=["#C44E52", "#4C78A8", "#54A24B"], height=0.55)
for i, v in enumerate(vals[::-1]):
    ax.text(v, i, f"  {v:,.0f}", va="center", fontsize=11, fontweight="bold")
ax.set_xlim(0, max(vals) * 1.18)
ax.set_xlabel("事件条数")
ax.set_title("淘宝用户行为 · 事件级转化漏斗（2017-11-25 ~ 12-03）", fontsize=13)
ax.text(0.55, -0.16,
        f"浏览→加购 {ev.cart/ev.pv*100:.2f}%   |   加购→购买 {ev.buy/ev.cart*100:.2f}%   |   "
        f"整体 {ev.buy/ev.pv*100:.2f}%",
        transform=ax.transAxes, fontsize=11)
fig.tight_layout()
fig.savefig(os.path.join(REPORTS, "01_funnel_event_level.png"), dpi=140)
plt.close(fig)

# ---------------- 2. Cohort 留存 ----------------
print("\n" + "=" * 70)
print("【2】Cohort 留存（窗口完整口径）")
print("=" * 70)
ret = q(f"""
WITH fb AS (
    SELECT user_id, MIN(CAST(to_timestamp(ts) AS DATE)) AS f
    FROM {WINDOW} WHERE behavior='buy' GROUP BY user_id
),
act AS (SELECT DISTINCT user_id, CAST(to_timestamp(ts) AS DATE) AS d FROM {WINDOW}),
rel AS (SELECT fb.user_id, fb.f, date_diff('day', fb.f, act.d) AS n FROM fb JOIN act USING(user_id)),
base AS (SELECT f AS 首购日, COUNT(DISTINCT user_id) AS 新增 FROM fb GROUP BY f),
agg AS (
    SELECT f AS 首购日,
           COUNT(DISTINCT CASE WHEN n=1 THEN user_id END) AS d1,
           COUNT(DISTINCT CASE WHEN n=3 THEN user_id END) AS d3
    FROM rel GROUP BY f
)
SELECT b.首购日, b.新增,
       CASE WHEN b.首购日 <= DATE '2017-12-02'
            THEN ROUND(a.d1*100.0/b.新增, 1) END AS 次日留存率,
       CASE WHEN b.首购日 <= DATE '2017-11-30'
            THEN ROUND(a.d3*100.0/b.新增, 1) END AS 第3日留存率
FROM base b JOIN agg a USING (首购日)
ORDER BY b.首购日
""")
print(ret.to_string(index=False))
ret.to_csv(os.path.join(TABLES, "cohort_retention.csv"), index=False, encoding="utf-8-sig")

plot_df = ret.dropna(subset=["次日留存率"])
fig, ax = plt.subplots(figsize=(10, 4.8))
ax.plot([str(x)[5:] for x in plot_df["首购日"]], plot_df["次日留存率"],
        marker="o", linewidth=2, color="#4C78A8")
for i, v in enumerate(plot_df["次日留存率"]):
    ax.annotate(f"{v}%", (i, v), textcoords="offset points", xytext=(0, 9), ha="center", fontsize=9)
ax.set_ylim(70, 100)
ax.set_ylabel("次日留存率 (%)")
ax.set_xlabel("首购日（Cohort）")
ax.set_title("各 Cohort 次日留存率（窗口仅 9 天，末尾 cohort 已剔除观测不足）", fontsize=13)
ax.grid(axis="y", alpha=.3)
fig.tight_layout()
fig.savefig(os.path.join(REPORTS, "02_cohort_d1_retention.png"), dpi=140)
plt.close(fig)

# ---------------- 3. RFM ----------------
print("\n" + "=" * 70)
print("【3】RFM 分层（R=距最后一次购买天数）")
print("=" * 70)
rfm = q(f"""
WITH u AS (
    SELECT user_id,
           COUNT(*)                              AS freq,
           SUM(behavior='buy')                   AS buy_cnt,
           COUNT(DISTINCT item_id)               AS item_cnt,
           CASE WHEN SUM(behavior='buy')=0 THEN NULL
                ELSE date_diff('day',
                      MAX(CASE WHEN behavior='buy' THEN CAST(to_timestamp(ts) AS DATE) END),
                      DATE '2017-12-03') END      AS r_days
    FROM {WINDOW} GROUP BY user_id
),
scored AS (
    SELECT *, 6 - NTILE(4) OVER (PARTITION BY (buy_cnt=0) ORDER BY COALESCE(r_days,0) ASC) AS r_score,
              NTILE(4)     OVER (PARTITION BY (buy_cnt=0) ORDER BY freq ASC)               AS f_score
    FROM u
),
seg AS (
    SELECT *, CASE WHEN buy_cnt=0 THEN 'P 未购买用户'
                   WHEN r_score>=4 AND f_score>=4 THEN '01 重要价值'
                   WHEN r_score>=4 AND f_score< 4 THEN '02 新晋高潜'
                   WHEN r_score< 4 AND f_score>=4 THEN '03 沉睡高价值'
                   ELSE '04 流失风险' END AS 分层
    FROM scored
)
SELECT 分层, COUNT(*) AS 人数,
       ROUND(COUNT(*)*100.0/SUM(COUNT(*)) OVER (),2) AS 占比,
       ROUND(AVG(freq),0) AS 平均行为次数,
       ROUND(AVG(buy_cnt),2) AS 平均购买次数
FROM seg GROUP BY 分层 ORDER BY 分层
""")
print(rfm.to_string(index=False))
rfm.to_csv(os.path.join(TABLES, "rfm_segments.csv"), index=False, encoding="utf-8-sig")

d = rfm.sort_values("人数")
fig, ax = plt.subplots(figsize=(10, 5))
ax.barh(d["分层"], d["人数"], color=["#E45756", "#F58518", "#4C78A8", "#72B7B2", "#54A24B"][:len(d)])
for i, (n, p) in enumerate(zip(d["人数"], d["占比"])):
    ax.text(n, i, f"  {n:,} ({p}%)", va="center", fontsize=10)
ax.set_xlim(0, d["人数"].max() * 1.28)
ax.set_xlabel("用户数")
ax.set_title("淘宝 UserBehavior · 用户分层（R=距最后购买天数, F=行为频次）", fontsize=13)
fig.tight_layout()
fig.savefig(os.path.join(REPORTS, "04_rfm_segments.png"), dpi=140)
plt.close(fig)

# ---------------- 4. 每日趋势 ----------------
daily = q(f"""
SELECT CAST(to_timestamp(ts) AS DATE) AS 日期,
       SUM(behavior='pv')   AS 浏览,
       SUM(behavior='cart') AS 加购,
       SUM(behavior='buy')  AS 购买
FROM {WINDOW} GROUP BY 日期 ORDER BY 日期
""")
daily.to_csv(os.path.join(TABLES, "daily_trend.csv"), index=False, encoding="utf-8-sig")

print("\n产物：")
for f in sorted(os.listdir(TABLES)):
    print(f"  reports/tables/{f}")
