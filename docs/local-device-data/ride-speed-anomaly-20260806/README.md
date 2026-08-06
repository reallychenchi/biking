# Ride Speed Anomaly Local Device Export

本目录保存 2026-08-06 从真机 `cc.chenchi.bike` 导出的本地骑行数据副本和只读分析结果。

这些文件包含真实轨迹坐标，属于敏感本地数据。`docs/local-device-data/.gitignore` 已配置为默认忽略数据库和 CSV/TSV 导出，避免误提交。

## 文件

- `default.store`: 真机 App 的 SwiftData SQLite 数据库副本。
- `default.store-shm` / `default.store-wal`: 本地只读 SQLite 打开时生成的辅助文件。
- `ride_summary.csv`: 所有骑行记录摘要。
- `top_speed_points.csv`: 系统速度最高的前 100 个轨迹点。
- `ride31_speed_spike_context.csv`: `ride_pk=31` 中 52 km/h 前后的原始点。
- `ride31_derived_speed_context.tsv`: 对 52 km/h 前后点按相邻坐标反推的速度。
- `analysis.md`: 本次异常值分析结论。

## 数据来源

- 设备：`陈池的iPhone`，Xcode `devicectl` 识别为 connected。
- Bundle ID：`cc.chenchi.bike`。
- 导出命令：`xcrun devicectl device copy from --domain-type appDataContainer --domain-identifier cc.chenchi.bike --source / ...`。
- 原始导出临时目录：`/tmp/bike-device-container-20260806164152`。
