# Bike iOS Architecture

本文描述当前仓库中已经由代码证明的结构。它是面向开发与 Codex 的架构地图，不替代产品需求；产品口径仍从 `docs/iOS骑行App需求文档.md` 开始核对。文中所有结论都附有代码路径；无法由仓库确认的事项统一标为“需要人工确认”。

## 系统目标

Bike 是一个本地优先的 iPhone 骑行记录应用：采集定位，计算轨迹、距离、全程时间、运动时间、速度与海拔统计，将完成的骑行保存在设备，并展示历史详情和轨迹。应用界面和业务代码位于 `iOS/bike/bike/`，产品基线位于 `docs/iOS骑行App需求文档.md`。

工程当前包含一个 App target、一个 Swift Testing 单元测试 target 和一个 XCTest UI 测试 target，定义在 `iOS/bike/bike.xcodeproj/project.pbxproj`。它们是 Xcode targets；`Domain/`、`Features/`、`Persistence/` 等只是同一 App target 内的源码目录，不是独立 Swift modules。

## 主要模块与职责

| 区域 | 职责 | 代码路径 |
| --- | --- | --- |
| 应用入口与组合根 | 创建 SwiftData 容器、具体仓储和全局应用模型；注册 AppDelegate；初始化友盟统计/APM | `iOS/bike/bike/bikeApp.swift` |
| 全局应用状态 | 持有 Tab 状态、骑行控制器、历史库、网络监视器；启动时加载历史并检查未完成骑行 | `iOS/bike/bike/AppModel.swift` |
| 根界面与生命周期桥接 | 组装骑行、历史、我的三个 Tab；把前后台事件转交骑行控制器 | `iOS/bike/bike/ContentView.swift` |
| 骑行功能 | 管理骑行状态机、运行任务、实时地图和指标、开始/结束/重试交互 | `iOS/bike/bike/Features/Ride/RideSessionController.swift`、`iOS/bike/bike/Features/Ride/RideView.swift` |
| 历史功能 | 加载、延迟删除及撤销记录；展示列表、带内存及磁盘缓存的异步轨迹缩略图、详情、速度分析图表和分段轨迹；将详情指标渲染为长图并调用系统分享面板 | `iOS/bike/bike/Features/History/RideLibrary.swift`、`iOS/bike/bike/Features/History/HistoryView.swift`、`iOS/bike/bike/Features/History/RideRouteGeometry.swift`、`iOS/bike/bike/Features/History/RideDetailView.swift`、`iOS/bike/bike/Features/History/RideSpeedChartsView.swift`、`iOS/bike/bike/Features/History/RideRouteView.swift`、`iOS/bike/bike/Services/RideRouteSnapshotRenderer.swift`、`iOS/bike/bike/Services/RideRouteSnapshotDiskCache.swift` |
| 我的功能 | 展示累计里程和个人最佳骑行记录，跳转对应详情页；在当前页面切换并持久化主题偏好；展示关于页和本地数据/定位用途说明 | `iOS/bike/bike/Features/Settings/SettingsView.swift` |
| 核心领域 | 定义骑行、轨迹点、进度、完成快照、指标公式、个人统计、基于轨迹点的速度距离分析和最快速度异常过滤 | `iOS/bike/bike/Domain/RideModels.swift`、`iOS/bike/bike/Domain/RideSpeedAnalysis.swift`、`iOS/bike/bike/Domain/RideSpeedAnomalyFilter.swift` |
| 定位校验与指标累计 | 校验位置/速度/轨迹段，累计带迟滞与超时规则的运动时间；过滤、平滑并累计海拔趋势 | `iOS/bike/bike/Domain/LocationSampleValidator.swift`、`iOS/bike/bike/Domain/MovementTimeAccumulator.swift`、`iOS/bike/bike/Domain/ElevationAccumulator.swift` |
| 展示格式 | 将米、米每秒、秒和日期转换为 UI 文本 | `iOS/bike/bike/Domain/RideFormatting.swift` |
| 定位服务 | 请求定位权限和临时精确定位；通过 `CLLocationUpdate` 输出异步更新；维护后台活动会话 | `iOS/bike/bike/Services/RideTrackingService.swift` |
| 网络状态 | 只通过 `NWPathMonitor` 发布离线状态；仓库没有自建 HTTP/API 客户端 | `iOS/bike/bike/Services/NetworkStatusMonitor.swift` |
| 日志 | 提供 ride、location、persistence 等 OSLog 分类 | `iOS/bike/bike/Services/AppLog.swift` |
| 持久化契约 | 定义业务所需的骑行写入、查询与删除接口 | `iOS/bike/bike/Persistence/RideRepository.swift` |
| SwiftData 实现 | 以 actor 隔离 ModelContext，映射领域模型与持久化实体 | `iOS/bike/bike/Persistence/SwiftDataRideRepository.swift`、`iOS/bike/bike/Persistence/RideEntities.swift` |
| 视觉设计 | 集中维护自适应语义色、外观映射和尺寸常量；需要精确品牌值的浅色/深色变体由 Asset Catalog 提供 | `iOS/bike/bike/Design/AppTheme.swift`、`iOS/bike/bike/Assets.xcassets/` |
| 第三方依赖 | CocoaPods 管理友盟 `UMCommon`、`UMAPM`、`UMDevice`；版本锁定在 lockfile | `iOS/bike/Podfile`、`iOS/bike/Podfile.lock` |
| 测试入口 | Swift Testing 覆盖领域、仓储和控制器；XCTest 覆盖主导航、关于页、启动和截图 | `iOS/bike/bikeTests/bikeTests.swift`、`iOS/bike/bikeUITests/bikeUITests.swift`、`iOS/bike/bikeUITests/bikeUITestsLaunchTests.swift` |

## 应用入口与依赖注入

`bikeApp` 是 `@main` 入口。`bikeApp.init()` 创建包含 `RideEntity`、`TrackPointEntity` 的持久化 `ModelContainer`，再创建 `SwiftDataRideRepository` 并注入 `AppModel`；容器同时通过 `.modelContainer` 注入 SwiftUI 环境（`iOS/bike/bike/bikeApp.swift`）。容器创建失败会 `fatalError`，不存在静默兜底。

`AppModel.init(repository:)` 是第二级组装点：同一 `RideRepository` 被注入 `RideLibrary` 和 `RideSessionController`，但具体的 `RideTrackingService` 与 `NetworkStatusMonitor` 仍由 `AppModel` 内部创建（`iOS/bike/bike/AppModel.swift`）。因此仓储可替换，定位服务可在 `RideSessionController` 单测中替换，而全局组合根尚未统一管理所有依赖。

友盟初始化走 `@UIApplicationDelegateAdaptor` 指向的 `AppDelegate`，与骑行业务依赖图并列。UMAPM 2.0.7 的页面监控仍会查询旧式 `UIApplicationDelegate.window`；兼容属性只把该查询映射到当前前台 `UIWindowScene.keyWindow`，窗口本身继续由 SwiftUI `WindowGroup` 管理，不创建第二个 `UIWindow`（`iOS/bike/bike/bikeApp.swift`）。

## 依赖方向

允许的当前主路径如下：

```text
bikeApp / AppDelegate
  -> AppModel + SwiftDataRideRepository + third-party telemetry
  -> ContentView
       -> Features (Ride / History / Settings)
            -> Domain models, validation, metrics, formatting
            -> RideRepository protocol
            -> RideTrackingProviding protocol
                 -> RideTrackingService -> CoreLocation
       -> NetworkStatusMonitor -> Network.framework

SwiftDataRideRepository -> RideRepository + Domain models + SwiftData entities
SwiftUI map views -> MapKit + GCJ-02 display-coordinate projection + read-only domain/controller projections
```

控制器和历史库依赖 `RideRepository` 协议，而不是 `SwiftDataRideRepository`（`iOS/bike/bike/Features/Ride/RideSessionController.swift`、`iOS/bike/bike/Features/History/RideLibrary.swift`）。定位控制器依赖 `RideTrackingProviding`，具体实现位于服务层（`iOS/bike/bike/Services/RideTrackingService.swift`）。

当前 `Domain/RideModels.swift` 和 `Domain/LocationSampleValidator.swift` 直接导入 CoreLocation，所以领域层并非完全平台无关；新增代码不要把 SwiftData、SwiftUI 或友盟依赖继续下沉到 Domain。

## 关键运行流程

### 1. 启动与恢复检查

1. `bikeApp.init()` 创建本地 ModelContainer、仓储和 AppModel（`iOS/bike/bike/bikeApp.swift`）。
2. `AppDelegate.application(_:didFinishLaunchingWithOptions:)` 配置并初始化友盟（`iOS/bike/bike/bikeApp.swift`）。
3. `ContentView.task` 调用 `AppModel.start()`（`iOS/bike/bike/ContentView.swift`）。
4. AppModel 加载已完成骑行，并查询 recording 状态的临时记录；发现未完成记录时提示用户删除（`iOS/bike/bike/AppModel.swift`、`iOS/bike/bike/Persistence/SwiftDataRideRepository.swift`）。

### 2. 开始与记录骑行

1. `RideView` 调用 `RideSessionController.startRide()`（`iOS/bike/bike/Features/Ride/RideView.swift`）。
2. 控制器先通过 `RideTrackingProviding.prepareForRide()` 检查服务、授权与精确定位，再创建 SwiftData 临时骑行；任一步失败都显示错误并停止（`iOS/bike/bike/Features/Ride/RideSessionController.swift`、`iOS/bike/bike/Services/RideTrackingService.swift`）。
3. 控制器启动 1 秒计时任务、5 秒 checkpoint 任务和定位异步流，并创建后台定位活动（`iOS/bike/bike/Features/Ride/RideSessionController.swift`）。
4. 每个样本先经过 `LocationSampleValidator`；有效水平点以原始 WGS-84 坐标进入内存中的 pendingPoints，更新距离、速度与 `MovementTimeAccumulator`；仅供 MapKit 实时绘制的 segments 会通过 `MapCoordinateConverter` 转为 GCJ-02。其海拔再由 `ElevationAccumulator` 独立进行垂直精度过滤、三点中值平滑和趋势累计（`iOS/bike/bike/Domain/LocationSampleValidator.swift`、`iOS/bike/bike/Domain/MapCoordinateConverter.swift`、`iOS/bike/bike/Domain/ElevationAccumulator.swift`、`iOS/bike/bike/Features/Ride/RideSessionController.swift`）。
5. checkpoint 将待写点和指标通过仓储增量写入；成功后才从内存队列移除，失败则保留并展示警告（`iOS/bike/bike/Features/Ride/RideSessionController.swift`、`iOS/bike/bike/Persistence/SwiftDataRideRepository.swift`）。

### 3. 结束、保存与失败重试

1. 结束时停止运行任务和定位服务，使用 `ContinuousClock` 计算全程时间，并生成完成快照（`iOS/bike/bike/Features/Ride/RideSessionController.swift`）。
2. 不超过 5 秒的骑行删除临时记录；更长骑行将剩余轨迹点与完成状态原子地交给仓储保存（`iOS/bike/bike/Features/Ride/RideSessionController.swift`）。
3. 保存成功后清空内存会话并触发 `RideLibrary.reload()`；失败时保留完成快照和待写点，进入 `saveFailed` 供显式重试（`iOS/bike/bike/AppModel.swift`、`iOS/bike/bike/Features/Ride/RideSessionController.swift`）。

### 4. 历史读取、轨迹与删除

历史读取采用**摘要优先、详情按需**两阶段设计，避免冷启动时全量加载轨迹点阻塞主线程。

1. `RideLibrary.reload()` 只调用 `completedRideSummaries()`，仓储使用 SwiftData predicate 在查询阶段过滤 completed 状态并按开始时间倒序返回 `[RideSummary]`；此路径不访问 `RideEntity.points` relationship，不触发 TrackPoint 加载或映射（`iOS/bike/bike/Features/History/RideLibrary.swift`、`iOS/bike/bike/Persistence/SwiftDataRideRepository.swift`）。
2. 列表项依次查询内存缓存和 App `Caches/RideRouteSnapshots` 磁盘缓存；**命中时不访问 repository**。缓存键仅依赖 `RideSummary` 的 ID、`updatedAt`、尺寸、scale 和外观（v5 格式，不修改 schema 不失效）。缓存未命中时才调用 `completedRide(id:)` 按单条 ID 加载轨迹，生成 MapKit 快照后写回两级缓存；snapshot 失败时保留不可交互的实时地图兜底，repository 失败显示明确错误图标（`iOS/bike/bike/Features/History/HistoryView.swift`、`iOS/bike/bike/Services/RideRouteSnapshotRenderer.swift`、`iOS/bike/bike/Services/RideRouteSnapshotDiskCache.swift`）。
3. 点击历史卡片进入详情页后，页面通过 `.task(id:)` 调用 `completedRide(id:)`，该查询使用专用 `FetchDescriptor` 并设置 `relationshipKeyPathsForPrefetching = [\RideEntity.points]` 预取轨迹关系；成功后才展示详情指标、速度图、轨迹页和分享按钮，期间显示加载进度，失败提供重试入口（`iOS/bike/bike/Features/History/RideDetailView.swift`、`iOS/bike/bike/Persistence/SwiftDataRideRepository.swift`）。
4. 详情页与轨迹缩略图共用 `RideRouteGeometry` 按 `segmentIndex` 重建轨迹段；在将持久化坐标交给 MapKit 前通过 `MapCoordinateConverter` 转为 GCJ-02（`iOS/bike/bike/Domain/MapCoordinateConverter.swift`、`iOS/bike/bike/Features/History/RideRouteGeometry.swift`、`iOS/bike/bike/Features/History/RideRouteView.swift`）。
5. 详情页使用完整 `RideRecord.points` 派生累计距离—有效系统速度曲线，并按固定绝对速度区间累计有效距离占比；最快速度使用异常过滤后的短窗口稳健峰值，不直接取单个瞬时速度最大值；速度图、轨迹页和分享复用同一份完整记录，不二次读取 repository（`iOS/bike/bike/Domain/RideSpeedAnalysis.swift`、`iOS/bike/bike/Domain/RideSpeedAnomalyFilter.swift`、`iOS/bike/bike/Features/History/RideSpeedChartsView.swift`、`iOS/bike/bike/Features/History/RideDetailView.swift`）。
6. 删除先从 UI 暂存移除并提供 4 秒撤销；整个删除与撤销流程只持有 `RideSummary`，不加载完整轨迹；超时后调用仓储删除，实体关系采用 cascade 删除轨迹点（`iOS/bike/bike/Features/History/RideLibrary.swift`、`iOS/bike/bike/Persistence/RideEntities.swift`）。

### 5. 网络状态

`NetworkStatusMonitor` 只把 `NWPath.status` 转换为 `isOffline`，`RideView` 据此显示地图加载提示（`iOS/bike/bike/Services/NetworkStatusMonitor.swift`、`iOS/bike/bike/Features/Ride/RideView.swift`）。它不控制骑行、持久化或友盟请求，也不提供 API 重试语义。

## 数据所有权

| 数据 | 权威所有者与生命周期 | 代码路径 |
| --- | --- | --- |
| 已完成/未完成骑行与轨迹点 | SwiftData `ModelContainer`；`RideEntity` 拥有 `TrackPointEntity`，删除规则为 cascade | `iOS/bike/bike/bikeApp.swift`、`iOS/bike/bike/Persistence/RideEntities.swift` |
| 海拔原始值与完成统计 | `TrackPointEntity` 保存可选海拔/垂直精度，`RideEntity` 保存可选累积升降和最低/最高海拔；旧记录不回填 `0` | `iOS/bike/bike/Domain/ElevationAccumulator.swift`、`iOS/bike/bike/Persistence/RideEntities.swift` |
| 活跃骑行运行态 | `RideSessionController.ActiveRide`；仅存在于进程内，pendingPoints 通过 checkpoint/完成保存转移到仓储 | `iOS/bike/bike/Features/Ride/RideSessionController.swift` |
| 历史页面投影与撤销窗口 | `RideLibrary`；`rides` 和 `pendingDelete` 是 `[RideSummary]` 仓储摘要投影；完整 `RideRecord`（含 points）只在详情页或缩略图缓存未命中时按 ID 加载，页面退出后释放，不常驻 library | `iOS/bike/bike/Features/History/RideLibrary.swift` |
| Tab、异常骑行提示 | `AppModel` 的进程内状态 | `iOS/bike/bike/AppModel.swift` |
| 地图底图 | MapKit 管理，仓库只拥有轨迹坐标和展示状态 | `iOS/bike/bike/Features/Ride/RideView.swift`、`iOS/bike/bike/Features/History/RideRouteView.swift` |
| 友盟统计/APM 数据 | 第三方 SDK 管理；仓库只包含初始化配置，实际采集字段、留存和上传策略无法从当前代码完整确定 | `iOS/bike/bike/bikeApp.swift`、`iOS/bike/Podfile.lock`；**需要人工确认** |

仓库没有账号、CloudKit、业务服务端或远端骑行仓储实现；`RideRepository` 当前唯一实现是 `SwiftDataRideRepository`（`iOS/bike/bike/Persistence/RideRepository.swift`、`iOS/bike/bike/Persistence/SwiftDataRideRepository.swift`）。

## 重要架构约束

- 最低部署版本由 Xcode 工程设为 iOS 18.0，App 仅面向 iPhone；定位流和后台会话使用 iOS 18 API（`iOS/bike/bike.xcodeproj/project.pbxproj`、`iOS/bike/bike/Services/RideTrackingService.swift`）。
- 业务层只能通过 `RideRepository` 读写骑行数据；不要在 View 或控制器中直接使用 ModelContext（`iOS/bike/bike/Persistence/RideRepository.swift`）。
- 定位必须先通过 `LocationSampleValidator`，阈值集中在命名配置中；不要在 View 中重复过滤或补造点（`iOS/bike/bike/Domain/LocationSampleValidator.swift`）。
- 全程时间使用 `ContinuousClock`；`startDate`/`endDate` 只承担持久化和展示语义（`iOS/bike/bike/Features/Ride/RideSessionController.swift`）。
- 运动时间使用 0.8 m/s 开始、0.3 m/s 停止的迟滞，并在速度超过 5 秒未更新时停止（`iOS/bike/bike/Domain/MovementTimeAccumulator.swift`）。
- SwiftUI 状态协调器和定位服务运行在 MainActor；SwiftData 仓储使用 ModelActor 隔离持久化上下文（`iOS/bike/bike/AppModel.swift`、`iOS/bike/bike/Services/RideTrackingService.swift`、`iOS/bike/bike/Persistence/SwiftDataRideRepository.swift`）。
- 关键失败必须在 UI 或状态机中可见并记录日志；存储初始化失败快速终止（`iOS/bike/bike/bikeApp.swift`、`iOS/bike/bike/Features/Ride/RideSessionController.swift`、`iOS/bike/bike/Services/AppLog.swift`）。
- 使用 CocoaPods 后应从 `iOS/bike/bike.xcworkspace` 构建，不从 `.xcodeproj` 构建；依赖声明和锁定分别位于 `iOS/bike/Podfile`、`iOS/bike/Podfile.lock`。

## 扩展点

- 新存储或同步实现：实现 `RideRepository`，在 `bikeApp.init()` 替换组合；同步冲突、认证和远端数据所有权需另行设计（`iOS/bike/bike/Persistence/RideRepository.swift`、`iOS/bike/bike/bikeApp.swift`）。
- 新定位来源或可控测试源：实现 `RideTrackingProviding` 并注入 `RideSessionController`（`iOS/bike/bike/Services/RideTrackingService.swift`、`iOS/bike/bike/Features/Ride/RideSessionController.swift`）。
- 调整轨迹质量和运动判定：修改命名配置及对应单测，而不是散落到页面（`iOS/bike/bike/Domain/LocationSampleValidator.swift`、`iOS/bike/bike/Domain/MovementTimeAccumulator.swift`、`iOS/bike/bikeTests/bikeTests.swift`）。
- 调整海拔精度、平滑或趋势判定：修改 `ElevationCalculationConfiguration` 和对应单测；不得在 View、控制器或仓储中复制阈值（`iOS/bike/bike/Domain/ElevationAccumulator.swift`、`iOS/bike/bikeTests/bikeTests.swift`）。
- 新增顶级功能：在 `AppTab`、`ContentView` 和必要的 AppModel 依赖中显式接入（`iOS/bike/bike/AppModel.swift`、`iOS/bike/bike/ContentView.swift`）。
- 新遥测提供方：当前入口集中在 AppDelegate，但尚无仓库内协议边界；若业务需要测试或开关，应先抽象其生命周期与隐私策略（`iOS/bike/bike/bikeApp.swift`）。

## 需要人工确认

1. 友盟统计/APM 的实际采集范围、用户同意流程、隐私清单、数据留存和发布合规策略。代码只能确认 SDK 已初始化（`iOS/bike/bike/bikeApp.swift`）。
2. `docs/iOS骑行App需求文档.md` 仍写明不接入统计/崩溃上报和“不支持删除”；这些与 `iOS/bike/bike/bikeApp.swift`、`iOS/bike/bike/Features/History/HistoryView.swift`、`iOS/bike/bike/Features/History/RideLibrary.swift` 不一致，需确定是更新需求还是回退实现。
3. `iOS/bike/Podfile` 声明 iOS 14.0，而 `iOS/bike/bike.xcodeproj/project.pbxproj` 和使用的 API 指向 iOS 18.0；需确认 Podfile 是否应统一为 18.0。
4. 友盟接入后，`bikeTests` 在当前 Xcode 26.3 环境编译时无法解析 `UMAPM`、`UMCommon` 模块；App Simulator build 成功。测试 target 是否应继承 Pods 搜索路径或通过入口隔离第三方 SDK，需人工确认后修复（目标定义见 `iOS/bike/bike.xcodeproj/project.pbxproj`）。
5. 正式品牌名、签名/发布环境、App Store 隐私声明和生产监控开关不在仓库文档中，**需要人工确认**（现有工程配置见 `iOS/bike/bike.xcodeproj/project.pbxproj`、`iOS/bike/bike/Info.plist`）。
