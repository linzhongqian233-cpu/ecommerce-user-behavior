# 依次运行 sql 目录下所有查询脚本（命令行版，不依赖 DBeaver）
param(
    [string]$MysqlExe = 'D:\mysql-8.0.21\bin\mysql.exe',
    [string]$SqlDir   = 'D:\dsh2\projects\ecommerce-user-behavior\sql'
)
$total = [System.Diagnostics.Stopwatch]::StartNew()
Get-ChildItem $SqlDir -Filter '*.sql' | Where-Object { $_.Name -ne '00_all_in_one.sql' } | Sort-Object Name | ForEach-Object {
    Write-Host ("`n===== {0} =====" -f $_.Name) -ForegroundColor Cyan
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $src = $_.FullName -replace '\\','/'
    & $MysqlExe -uroot -p123456 --default-character-set=utf8mb4 -t -e "source $src" 2>&1 |
        Where-Object { $_ -notmatch 'Warning' }
    $sw.Stop()
    Write-Host ("[完成] {0:N1} 秒" -f $sw.Elapsed.TotalSeconds) -ForegroundColor Green
}
$total.Stop()
Write-Host ("`n全部完成，总耗时 {0:N1} 秒" -f $total.Elapsed.TotalSeconds) -ForegroundColor Yellow