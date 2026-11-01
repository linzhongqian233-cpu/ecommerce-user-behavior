# -*- coding: utf-8 -*-
"""CSV → Parquet（3.42 GB → 632 MB，约 7 秒）

UserBehavior.csv 无表头，必须显式声明列名，否则 DuckDB 会把列名认成 column0。
"""
import duckdb
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import DATA_CSV, DATA_PARQUET


def main():
    if not os.path.exists(DATA_CSV):
        print(f"[错误] 找不到 CSV: {DATA_CSV}")
        print("请设置环境变量 UB_CSV 指向 UserBehavior.csv")
        sys.exit(1)

    os.makedirs(os.path.dirname(DATA_PARQUET), exist_ok=True)

    if os.path.exists(DATA_PARQUET):
        size = os.path.getsize(DATA_PARQUET) / 1024 / 1024
        print(f"Parquet 已存在，跳过转换：{DATA_PARQUET} ({size:.0f} MB)")
        return

    t = time.time()
    duckdb.sql(f"""
        COPY (
            SELECT * FROM read_csv('{DATA_CSV}', header=false,
                columns={{'user_id':'BIGINT','item_id':'BIGINT',
                          'category_id':'BIGINT','behavior':'VARCHAR','ts':'BIGINT'}})
        ) TO '{DATA_PARQUET}' (FORMAT PARQUET, COMPRESSION ZSTD)
    """)
    size = os.path.getsize(DATA_PARQUET) / 1024 / 1024
    print(f"转换完成：{DATA_PARQUET}  {size:.0f} MB，耗时 {time.time() - t:.1f} 秒")


if __name__ == "__main__":
    main()
