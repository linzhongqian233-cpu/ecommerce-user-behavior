# -*- coding: utf-8 -*-
"""统一路径配置

所有脚本通过环境变量覆盖默认路径，方便换机器复现：
    set UB_CSV=D:/data/UserBehavior.csv
    set UB_PARQUET=D:/data/user_behavior.parquet
"""
import os

# 项目根目录（scripts/ 的上一级）
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 数据路径（默认值对应作者本机；换机器请用环境变量覆盖）
DATA_CSV = os.environ.get("UB_CSV", "D:/datasets/raw/UserBehavior.csv")
DATA_PARQUET = os.environ.get("UB_PARQUET", "D:/datasets/processed/user_behavior.parquet")

# 输出目录
REPORTS = os.path.join(PROJECT_ROOT, "reports")
TABLES = os.path.join(REPORTS, "tables")

# 数据时间窗口（北京时间 2017-11-25 00:00 ~ 2017-12-03 23:59）
TS_MIN = 1511539200
TS_MAX = 1512316799

# 分析用的数据源表达式
PARQUET_SRC = f"read_parquet('{DATA_PARQUET}')"
WINDOW = f"(SELECT * FROM {PARQUET_SRC} WHERE ts BETWEEN {TS_MIN} AND {TS_MAX})"
