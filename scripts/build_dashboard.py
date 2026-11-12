# -*- coding: utf-8 -*-
"""从 Parquet 生成数据 + 输出单页 ECharts 看板（dashboard/index.html）。

用法: python scripts/build_dashboard.py
前置: D:/datasets/processed/user_behavior.parquet
"""
import duckdb
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import WINDOW as W, PROJECT_ROOT

OUT_DIR = os.path.join(PROJECT_ROOT, "dashboard")


def df(sql):
    return duckdb.sql(sql).df()


# ---------- 1. 漏斗（事件级 + 人级） ----------
f_ev = df(f"""
SELECT COUNT(*) FILTER (WHERE behavior='pv')   AS pv,
       COUNT(*) FILTER (WHERE behavior='fav')  AS fav,
       COUNT(*) FILTER (WHERE behavior='cart') AS cart,
       COUNT(*) FILTER (WHERE behavior='buy')  AS buy
FROM {W}
""").iloc[0]

f_pu = df(f"""
SELECT COUNT(DISTINCT CASE WHEN behavior='pv'   THEN user_id END) AS pv,
       COUNT(DISTINCT CASE WHEN behavior='cart' THEN user_id END) AS cart,
       COUNT(DISTINCT CASE WHEN behavior='buy'  THEN user_id END) AS buy
FROM {W}
""").iloc[0]

# ---------- 2. 每日趋势 ----------
daily = df(f"""
SELECT CAST(to_timestamp(ts) AS DATE) AS d,
       COUNT(*) FILTER (WHERE behavior='pv')   AS pv,
       COUNT(*) FILTER (WHERE behavior='cart') AS cart,
       COUNT(*) FILTER (WHERE behavior='buy')  AS buy
FROM {W} GROUP BY 1 ORDER BY 1
""")

# ---------- 3. Cohort 留存 ----------
ret = df(f"""
WITH fb AS (
  SELECT user_id, MIN(CAST(to_timestamp(ts) AS DATE)) AS f
  FROM {W} WHERE behavior='buy' GROUP BY user_id
),
act AS (SELECT DISTINCT user_id, CAST(to_timestamp(ts) AS DATE) AS d FROM {W}),
rel AS (SELECT fb.user_id, fb.f, date_diff('day', fb.f, act.d) AS n FROM fb JOIN act USING(user_id)),
base AS (SELECT f, COUNT(DISTINCT user_id) AS 新增 FROM fb GROUP BY f),
agg AS (
  SELECT f,
         COUNT(DISTINCT CASE WHEN n=1 THEN user_id END) AS d1,
         COUNT(DISTINCT CASE WHEN n=3 THEN user_id END) AS d3
  FROM rel GROUP BY f
)
SELECT b.f AS 首购日, b.新增,
       ROUND(a.d1*100.0/b.新增,1) AS d1率,
       ROUND(a.d3*100.0/b.新增,1) AS d3率
FROM base b JOIN agg a USING(f) ORDER BY b.f
""")

# ---------- 4. RFM ----------
rfm = df(f"""
WITH u AS (
  SELECT user_id,
         COUNT(*)                                AS freq,
         COUNT(*) FILTER (WHERE behavior='buy')  AS buy_cnt,
         CASE WHEN COUNT(*) FILTER (WHERE behavior='buy') = 0 THEN NULL
              ELSE date_diff('day',
                     MAX(CASE WHEN behavior='buy' THEN CAST(to_timestamp(ts) AS DATE) END),
                     DATE '2017-12-03') END      AS r_buy_days
  FROM {W} GROUP BY user_id
),
scored AS (
  SELECT *, 6 - NTILE(4) OVER (PARTITION BY (buy_cnt=0) ORDER BY COALESCE(r_buy_days,0) ASC) AS r_score,
            NTILE(4) OVER (PARTITION BY (buy_cnt=0) ORDER BY freq ASC) AS f_score
  FROM u
)
SELECT CASE WHEN buy_cnt = 0 THEN 'P 未购买'
            WHEN r_score>=4 AND f_score>=4 THEN '01 重要价值'
            WHEN r_score>=4 AND f_score< 4 THEN '02 新晋高潜'
            WHEN r_score< 4 AND f_score>=4 THEN '03 沉睡高价值'
            ELSE '04 流失风险' END AS 分层,
       COUNT(*) AS 人数, ROUND(AVG(freq),0) AS 平均行为
FROM scored GROUP BY 分层 ORDER BY 分层
""")

# ---------- 组装 ----------
data = {
    "funnel_event": {
        "stages": ["浏览 pv", "加购 cart", "购买 buy"],
        "values": [int(f_ev.pv), int(f_ev.cart), int(f_ev.buy)],
    },
    "funnel_person": {
        "stages": ["浏览", "加购", "购买"],
        "values": [int(f_pu.pv), int(f_pu.cart), int(f_pu.buy)],
    },
    "daily": {
        "dates": [str(x) for x in daily["d"]],
        "pv": [int(x) for x in daily["pv"]],
        "cart": [int(x) for x in daily["cart"]],
        "buy": [int(x) for x in daily["buy"]],
    },
    "retention": {
        "cohorts": [str(x) for x in ret["首购日"]],
        "size": [int(x) for x in ret["新增"]],
        "d1": [None if x != x else float(x) for x in ret["d1率"]],
        "d3": [None if x != x else float(x) for x in ret["d3率"]],
    },
    "rfm": {
        "segments": [str(x) for x in rfm["分层"]],
        "counts": [int(x) for x in rfm["人数"]],
        "avg_freq": [int(x) for x in rfm["平均行为"]],
    },
}

TEMPLATE = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>电商用户行为分析 · 看板</title>
<script src="echarts.min.js"></script>
<style>
  :root { --bg:#f7f8fa; --card:#fff; --ink:#1f2328; --sub:#6b7280; --line:#e5e7eb;
          --blue:#4C78A8; --green:#54A24B; --red:#E45756; --orange:#F58518; }
  * { box-sizing:border-box; }
  body { margin:0; background:var(--bg); color:var(--ink);
         font-family:-apple-system,"Segoe UI","Microsoft YaHei",sans-serif; }
  header { background:linear-gradient(120deg,#1e3a5f,#2f6690); color:#fff; padding:32px 40px 28px; }
  header h1 { margin:0 0 10px; font-size:24px; font-weight:600; letter-spacing:.5px; }
  header p { margin:0; opacity:.9; font-size:14px; line-height:1.7; max-width:1000px; }
  .wrap { max-width:1280px; margin:0 auto; padding:28px 24px 60px; }
  .kpis { display:grid; grid-template-columns:repeat(auto-fit,minmax(200px,1fr)); gap:16px; margin-bottom:24px; }
  .kpi { background:var(--card); border:1px solid var(--line); border-radius:10px; padding:18px 20px; }
  .kpi .label { color:var(--sub); font-size:13px; margin-bottom:8px; }
  .kpi .value { font-size:28px; font-weight:600; line-height:1.1; }
  .kpi .hint { color:var(--sub); font-size:12px; margin-top:6px; }
  .grid { display:grid; grid-template-columns:1fr 1fr; gap:20px; }
  @media (max-width:900px){ .grid{ grid-template-columns:1fr; } }
  .card { background:var(--card); border:1px solid var(--line); border-radius:10px; padding:18px 20px 8px; }
  .card h2 { margin:0 0 4px; font-size:16px; font-weight:600; }
  .card .desc { color:var(--sub); font-size:12.5px; margin:0 0 8px; line-height:1.6; }
  .chart { width:100%; height:340px; }
  .full { grid-column:1 / -1; }
  footer { text-align:center; color:var(--sub); font-size:12.5px; padding:28px 0 0; line-height:1.8; }
  code { background:#eef1f5; padding:1px 5px; border-radius:4px; font-size:12px; }
</style>
</head>
<body>
<header>
  <h1>电商用户行为分析 · 数据看板</h1>
  <p>数据：淘宝 UserBehavior（阿里天池 dataset/649），100,150,807 条行为日志，2017-11-25 ~ 12-03（9 天）&nbsp;|&nbsp;
     工具：DuckDB + Python + ECharts</p>
  <p><strong>核心结论：</strong>浏览→加购仅 6.17%，是全链路最大漏点；同时 31.94% 的用户 9 天内人均 79 次行为却零购买——问题不在流量，在加购环节缺少钩子。</p>
</header>

<div class="wrap">
  <div class="kpis" id="kpis"></div>

  <div class="grid">
    <div class="card">
      <h2>转化漏斗（事件级）</h2>
      <p class="desc">按行为条数统计。浏览→加购 6.17% 是全链路最大漏点；加购→购买 36.45%，说明加购后下单意愿强。</p>
      <div class="chart" id="funnel"></div>
    </div>
    <div class="card">
      <h2>每日行为量趋势</h2>
      <p class="desc">9 天窗口内浏览、加购、购买的事件量变化，可观察到明显的周末效应。</p>
      <div class="chart" id="daily"></div>
    </div>
    <div class="card">
      <h2>Cohort 次日/第 3 日留存</h2>
      <p class="desc">以首购日分组，看第 N 天是否仍有任意行为。窗口不足的 cohort 留空而非填 0。</p>
      <div class="chart" id="retention"></div>
    </div>
    <div class="card">
      <h2>用户分层（RFM 修正版）</h2>
      <p class="desc">R = 距最后一次购买天数，F = 9 天行为频次。未购买用户单列，占 31.94%。</p>
      <div class="chart" id="rfm"></div>
    </div>
    <div class="card full">
      <h2>事件级 vs 人级漏斗对比</h2>
      <p class="desc">同一份数据，两种口径的整体转化率相差 12 倍（2.25% vs 68.33%）。对外汇报必须注明口径。</p>
      <div class="chart" id="compare" style="height:380px"></div>
    </div>
  </div>

  <footer>
    数据局限：窗口仅 9 天（无法计算 30 日留存）· 无 session_id（无法做严格访问级漏斗）· 样本为活跃用户（留存偏高，不可作行业基准）· 无金额字段（GMV/LTV 不可计算）<br>
    全部 SQL 与报告见仓库 <code>sql/</code> 与 <code>reports/01_findings.md</code>
  </footer>
</div>

<script>
const D = __DATA__;

// KPI
const fe = D.funnel_event, fp = D.funnel_person;
const kpis = [
  { label:'分析事件数', value:(fe.values[0]+fe.values[1]+fe.values[2]).toLocaleString(), hint:'9 天窗口，已剔除 5.5 万行脏时间戳' },
  { label:'浏览 → 加购', value:(fe.values[1]/fe.values[0]*100).toFixed(2)+'%', hint:'最大漏点' },
  { label:'加购 → 购买', value:(fe.values[2]/fe.values[1]*100).toFixed(2)+'%', hint:'加购后意愿强' },
  { label:'整体转化率', value:(fe.values[2]/fe.values[0]*100).toFixed(2)+'%', hint:'事件级口径' },
  { label:'零购买用户占比', value:(D.rfm.counts[D.rfm.segments.findIndex(s=>s.indexOf('未购买')>=0)]/fp.values[0]*100).toFixed(2)+'%', hint:'来了但没买' },
];
document.getElementById('kpis').innerHTML = kpis.map(k =>
  `<div class="kpi"><div class="label">${k.label}</div><div class="value">${k.value}</div><div class="hint">${k.hint}</div></div>`
).join('');

// 漏斗
const c1 = echarts.init(document.getElementById('funnel'));
c1.setOption({
  tooltip:{ trigger:'item', formatter:p=>`${p.name}<br/>${p.value.toLocaleString()}<br/>占比 ${p.data.pct}` },
  series:[{
    type:'funnel', left:'12%', width:'72%', top:20, bottom:20, minSize:'28%',
    sort:'descending', gap:4,
    label:{ show:true, position:'inside', formatter:p=>`${p.name}\\n${p.data.pct}`, color:'#fff', fontSize:12 },
    itemStyle:{ borderWidth:0 },
    data: D.funnel_event.stages.map((s,i)=>({
      name:s, value: D.funnel_event.values[i],
      pct: i===0 ? '100%' : (D.funnel_event.values[i]/D.funnel_event.values[0]*100).toFixed(2)+'%'
    })),
    color:['#4C78A8','#F58518','#54A24B'],
  }]
});

// 每日趋势
const c2 = echarts.init(document.getElementById('daily'));
c2.setOption({
  tooltip:{ trigger:'axis' },
  legend:{ data:['浏览','加购','购买'], bottom:0, itemWidth:12, itemHeight:8, textStyle:{ fontSize:11 } },
  grid:{ left:70, right:24, top:20, bottom:48 },
  xAxis:{ type:'category', data:D.daily.dates, axisLabel:{ fontSize:10, rotate:30 } },
  yAxis:{ type:'value', axisLabel:{ formatter:v=>v>=1e6?(v/1e6).toFixed(0)+'M':v } },
  series:[
    { name:'浏览', type:'line', smooth:true, symbolSize:5, data:D.daily.pv, itemStyle:{color:'#4C78A8'} },
    { name:'加购', type:'line', smooth:true, symbolSize:5, data:D.daily.cart, itemStyle:{color:'#F58518'} },
    { name:'购买', type:'line', smooth:true, symbolSize:5, data:D.daily.buy, itemStyle:{color:'#54A24B'} },
  ]
});

// 留存
const c3 = echarts.init(document.getElementById('retention'));
c3.setOption({
  tooltip:{ trigger:'axis' },
  legend:{ data:['次日留存','第3日留存'], bottom:0, itemWidth:12, itemHeight:8, textStyle:{ fontSize:11 } },
  grid:{ left:56, right:24, top:20, bottom:52 },
  xAxis:{ type:'category', data:D.retention.cohorts, axisLabel:{ fontSize:10, rotate:30 } },
  yAxis:{ type:'value', min:60, max:100, axisLabel:{ formatter:'{value}%' } },
  series:[
    { name:'次日留存', type:'bar', data:D.retention.d1, itemStyle:{color:'#4C78A8', borderRadius:[3,3,0,0]}, label:{show:true,position:'top',fontSize:10,formatter:p=>p.value==null?'':p.value+'%'} },
    { name:'第3日留存', type:'bar', data:D.retention.d3, itemStyle:{color:'#72B7B2', borderRadius:[3,3,0,0]}, label:{show:true,position:'top',fontSize:10,formatter:p=>p.value==null?'':p.value+'%'} },
  ]
});

// RFM
const c4 = echarts.init(document.getElementById('rfm'));
const rfmSorted = D.rfm.segments.map((s,i)=>({s, c:D.rfm.counts[i], f:D.rfm.avg_freq[i]}))
                   .sort((a,b)=>a.c-b.c);
c4.setOption({
  tooltip:{ trigger:'axis', axisPointer:{type:'shadow'},
            formatter:p=>`${p[0].name}<br/>人数 ${p[0].value.toLocaleString()}<br/>人均行为 ${p[0].data.f} 次` },
  grid:{ left:120, right:80, top:16, bottom:28 },
  xAxis:{ type:'value', axisLabel:{ formatter:v=>v>=1000?(v/1000).toFixed(0)+'k':v } },
  yAxis:{ type:'category', data:rfmSorted.map(x=>x.s), axisLabel:{ fontSize:11 } },
  series:[{
    type:'bar', data:rfmSorted.map(x=>({value:x.c, f:x.f})),
    itemStyle:{ color:p=>['#E45756','#F58518','#4C78A8','#72B7B2','#54A24B'][p.dataIndex%5], borderRadius:[0,3,3,0] },
    label:{ show:true, position:'right', fontSize:11,
            formatter:p=>p.value.toLocaleString()+'  ('+(p.value/fp.values[0]*100).toFixed(1)+'%)' }
  }]
});

// 两口径对比
const c5 = echarts.init(document.getElementById('compare'));
c5.setOption({
  tooltip:{ trigger:'axis' },
  legend:{ data:['事件级转化率','人级转化率'], bottom:0, itemWidth:12, itemHeight:8 },
  grid:{ left:70, right:40, top:24, bottom:52 },
  xAxis:{ type:'category', data:['浏览→加购','加购→购买','整体转化'] },
  yAxis:{ type:'value', max:100, axisLabel:{ formatter:'{value}%' } },
  series:[
    { name:'事件级转化率', type:'bar', data:[
        +(fe.values[1]/fe.values[0]*100).toFixed(2),
        +(fe.values[2]/fe.values[1]*100).toFixed(2),
        +(fe.values[2]/fe.values[0]*100).toFixed(2)],
      itemStyle:{color:'#4C78A8', borderRadius:[4,4,0,0]}, label:{show:true,position:'top',formatter:'{c}%'} },
    { name:'人级转化率', type:'bar', data:[
        +(fp.values[1]/fp.values[0]*100).toFixed(2),
        +(fp.values[2]/fp.values[1]*100).toFixed(2),
        +(fp.values[2]/fp.values[0]*100).toFixed(2)],
      itemStyle:{color:'#E45756', borderRadius:[4,4,0,0]}, label:{show:true,position:'top',formatter:'{c}%'} },
  ]
});

window.addEventListener('resize', ()=>{ [c1,c2,c3,c4,c5].forEach(c=>c.resize()); });
</script>
</body>
</html>
"""

html = TEMPLATE.replace("__DATA__", json.dumps(data, ensure_ascii=False, indent=1))
os.makedirs(OUT_DIR, exist_ok=True)
path = os.path.join(OUT_DIR, "index.html")
with open(path, "w", encoding="utf-8") as f:
    f.write(html)

print(f"看板已生成: {path}  ({os.path.getsize(path)/1024:.0f} KB)")
print(f"漏斗事件级: {data['funnel_event']['values']}")
print(f"漏斗人级:   {data['funnel_person']['values']}")
print(f"RFM: {list(zip(data['rfm']['segments'], data['rfm']['counts']))}")
