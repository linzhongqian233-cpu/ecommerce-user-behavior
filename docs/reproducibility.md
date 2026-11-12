# 复现指南与验证记录

## 1. 环境要求

| 项 | 版本 | 说明 |
|---|---|---|
| Python | 3.12 | `pandas 3.1` / `duckdb 2.0` / `matplotlib 3.11` |
| MySQL | 8.0+ | 仅方言验证需要，纯分析用 DuckDB 即可 |
| 内存 | 建议 8 GB+ | Parquet 转换时会占用较多内存 |

```bash
py -m pip install -r requirements.txt
```

## 2. 数据获取

淘宝用户行为数据集（UserBehavior），1 亿条，约 3.4 GB：

- 阿里天池：https://tianchi.aliyun.com/dataset/649 （需登录）
- 数据特点：**无表头**，5 列纯数据，字段为 `user_id, item_id, category_id, behavior, ts`

放到任意目录后，用环境变量指向它：

```powershell
$env:UB_CSV     = "D:/datasets/raw/UserBehavior.csv"
$env:UB_PARQUET = "D:/datasets/processed/user_behavior.parquet"
```

> 不设环境变量时，脚本会用作者本机的默认路径（`scripts/common.py` 里可改）。

## 3. 三步跑通

```powershell
# 1) CSV → Parquet（3.42 GB → 632 MB）
py scripts/to_parquet.py

# 2) 全流程分析（漏斗 / 留存 / RFM）
py scripts/run_analysis.py

# 3) 重新生成看板
py scripts/build_dashboard.py
```

## 4. 预期输出（实测记录）

| 步骤 | 输出 | 实测耗时 |
|---|---|---|
| `to_parquet.py` | `user_behavior.parquet` 632 MB | **6.7 秒** |
| `run_analysis.py` | 3 张 PNG + 4 份 CSV | 约 60 秒 |
| `build_dashboard.py` | `dashboard/index.html` 12 KB | 约 40 秒 |

**关键数字（用于校验是否跑对）**：

| 指标 | 预期值 |
|---|---|
| 总行数 | 100,150,807 |
| 事件级漏斗 浏览 | 89,660,688 |
| 事件级漏斗 加购 | 5,530,446（**6.17%**）|
| 事件级漏斗 购买 | 2,015,839（**36.45%**）|
| 整体转化率 | **2.25%** |
| 零购买用户占比 | **31.94%** |
| 窗口完整 cohort 次日留存 | **81.3%** |

## 5. MySQL 方言验证（可选）

```powershell
# 抽样 1000 万行进 MySQL
mysql -uroot -p --local-infile=1 -e "source sql/00_all_in_one.sql"
```

或在 DBeaver 中打开 `sql/01_funnel.sql`，**`Ctrl+A` 全选后按 `Alt+X`**（不是 `Ctrl+Enter`）。

**实测结果**：9,980,307 行，导入 69 秒，四个 SQL 文件全部通过。

## 6. 常见问题

| 现象 | 原因 | 解决 |
|---|---|---|
| `Binder Error: Referenced column "behavior" not found` | CSV 无表头，DuckDB 把列名认成 `column0` | 用 `read_csv(..., columns={...})` 显式声明列名 |
| `SQL 错误 [1064]` 且 SQL 以 `USE ecommerce; WITH ...` 开头 | 选用了多段后按 `Ctrl+Enter`，多条语句被拼成一条发给 JDBC | 改用 `Alt+X` 执行整个脚本 |
| `Table 'practice_demo.student' doesn't exist` | DBeaver 右上角数据库下拉框没选对 | 选 `ecommerce`，或依赖脚本里的 `USE ecommerce;` |
| MySQL 报 `COUNT(*) FILTER` 语法错误 | `FILTER` 是 PostgreSQL/DuckDB 语法，MySQL 不支持 | 改成 `SUM(condition)` |
| `mysqld` 直接崩溃退出 | MySQL 8.0.21 优化器缺陷：`CROSS JOIN` 单行 CTE + 窗口函数 | 改成标量子查询 |
| 图表中文显示为方块 | matplotlib 未指定中文字体 | 已设置 `font.sans-serif = ['Microsoft YaHei']` |

## 7. 已验证清单

- [x] `to_parquet.py` 可独立运行，重复运行会跳过
- [x] `run_analysis.py` 输出与 `reports/` 中已提交的图表一致
- [x] `build_dashboard.py` 可重建 `dashboard/index.html`
- [x] 四个 SQL 文件在 MySQL 8.0.21 上全部执行通过
- [x] 看板页面在 GitHub Pages 上可访问（HTTP 200）
- [ ] 换一台机器从零复现（需要重新下载 3.4 GB 数据，未做端到端验证）
