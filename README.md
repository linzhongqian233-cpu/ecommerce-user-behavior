# 电商用户行为分析与转化优化

> **一句话结论**：（做完后回来填 —— 例：定位到「加购→购买」环节转化率仅 32%，低于行业均值，主因是加购后 48 小时内无任何触达；建议上线加购未支付提醒，预估月增 GMV 约 xx 万元。）

---

## 1. 背景与目标

- **业务问题**：平台整体转化率下滑，需要定位是「流量质量」还是「转化链路」的问题。
- **分析目标**：
  1. 还原用户从浏览到下单的完整链路，量化每一环的流失
  2. 找出转化率最低、且可干预的环节
  3. 给出可执行的运营动作与预估收益
- **成功标准**：结论能被业务方直接执行（谁、在什么时点、对哪批人、做什么）

## 2. 数据说明

| 项 | 内容 |
|---|---|
| 数据源 | 阿里天池 UserBehavior（约 1 亿条，2017-11-25 ～ 2017-12-03）|
| 字段 | `user_id` 用户、`item_id` 商品、`category_id` 品类、`behavior` 行为、`timestamp` 时间戳 |
| 行为类型 | `pv` 浏览 / `fav` 收藏 / `cart` 加购 / `buy` 购买 |
| 已知局限 | 无金额字段（只能用行为量代替 GMV）、无渠道来源、仅 9 天 |
| 替代练习库 | 本机 `school_db`（13.6 万行教务数据），先练方法再换正式数据 |

## 3. 分析框架

```
流量 → 浏览 → 加购/收藏 → 下单购买
       ↓        ↓           ↓
     品类分布  流失环节    复购与留存
```

| 模块 | 回答什么问题 | 对应 SQL |
|---|---|---|
| 漏斗 | 哪一环流失最多 | `sql/01_funnel.sql` |
| 留存 | 用户来了还会不会回来 | `sql/02_cohort_retention.sql` |
| 分层 | 该优先运营哪批人 | `sql/03_rfm.sql` |
| 归因 | 转化率异常是谁造成的 | `sql/04_anomaly.sql` |

## 4. 核心发现

（做完后按「现象 → 原因 → 建议」写，每条不超过 3 行）

1. **现象**：
2. **原因**：
3. **建议**：

## 5. 交付物

- [ ] `notebooks/01_eda.ipynb` 数据清洗与探索
- [ ] `sql/` 四份可复用的分析 SQL
- [ ] `dashboard/` Tableau Public 看板（公开链接贴这里：）
- [ ] `reports/analysis.pdf` 2 页分析报告

## 6. 目录结构

```
ecommerce-user-behavior/
├── README.md
├── requirements.txt
├── sql/                 分析 SQL（含口径注释）
├── notebooks/           Jupyter 探索
├── dashboard/           看板文件 / 链接说明
├── reports/             分析报告
└── data/                原始数据（不入库，见 .gitignore）
```

## 7. 环境与运行

```powershell
# 安装依赖
py -m pip install -r requirements.txt

# 用 DuckDB 直接查 CSV（1 亿行不需要导入）
py -c "import duckdb; duckdb.sql(\"SELECT behavior, COUNT(*) FROM 'data/UserBehavior.csv' GROUP BY 1\").show()"

# 用 MySQL 查（先导入抽样数据）
mysql -uroot -p -e "source sql/00_load_mysql.sql"
```

## 8. 口径定义（避免和业务方吵架）

| 指标 | 定义 | 注意点 |
|---|---|---|
| 活跃用户 | 当天有任意行为（pv/fav/cart/buy）的去重 `user_id` | 不按设备去重 |
| 加购转化率 | 加购人数 / 浏览人数 | 分母是「人」不是「次」|
| 复购率 | 30 天内下单 ≥2 次的人数 / 下单人数 | 首单当天二次下单也算 |
| 留存 | 首购后第 N 天有任意行为 | 用 `DATEDIFF(行为日, 首购日)`，不是自然日 |
