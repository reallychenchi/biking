import AppIntents
import Foundation
import OSLog

private enum RideShortcutText {
    static let startSuccess: IntentDialog = "已开始骑行。"
    static let alreadyRecording: IntentDialog = "骑行已经在记录中。"
    static let startInProgress: IntentDialog = "正在准备开始骑行。"
    static let startFailedPrefix = "无法开始骑行："

    static let endSuccess: IntentDialog = "已结束骑行。"
    static let notRecording: IntentDialog = "当前没有正在记录的骑行。"
    static let endInProgress: IntentDialog = "正在结束骑行。"
    static let saveFailedPrefix = "骑行结束了，但保存失败："
    static let saveFailed: IntentDialog = "骑行结束了，但保存失败。"
}

struct StartRideIntent: AppIntent {
    static let title: LocalizedStringResource = "开始骑行"
    static let description = IntentDescription("开始记录通勤骑行，并计算实时速度、距离和时间。")
    static let openAppWhenRun = true

    @AppDependency private var appModel: AppModel

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        appModel.selectedTab = .ride

        switch appModel.rideController.phase {
        case .idle, .saveFailed:
            await appModel.rideController.startRide()
        case .recording:
            return .result(dialog: RideShortcutText.alreadyRecording)
        case .requestingAuthorization, .starting, .finishing:
            return .result(dialog: RideShortcutText.startInProgress)
        }

        switch appModel.rideController.phase {
        case .recording:
            AppLog.ride.info("Ride started from Siri shortcut")
            return .result(dialog: RideShortcutText.startSuccess)
        case .idle, .saveFailed:
            if let notice = appModel.rideController.notice {
                return .result(dialog: "\(RideShortcutText.startFailedPrefix)\(notice.message)")
            }
            return .result(dialog: RideShortcutText.startInProgress)
        case .requestingAuthorization, .starting, .finishing:
            return .result(dialog: RideShortcutText.startInProgress)
        }
    }
}

struct EndRideIntent: AppIntent {
    static let title: LocalizedStringResource = "结束骑行"
    static let description = IntentDescription("结束当前通勤骑行，并保存骑行记录。")
    static let openAppWhenRun = true

    @AppDependency private var appModel: AppModel

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        appModel.selectedTab = .ride

        switch appModel.rideController.phase {
        case .recording:
            await appModel.rideController.endRide()
        case .finishing:
            return .result(dialog: RideShortcutText.endInProgress)
        case .idle, .requestingAuthorization, .starting, .saveFailed:
            return .result(dialog: RideShortcutText.notRecording)
        }

        switch appModel.rideController.phase {
        case .idle:
            AppLog.ride.info("Ride ended from Siri shortcut")
            if let notice = appModel.rideController.notice {
                return .result(dialog: "\(notice.message)")
            }
            return .result(dialog: RideShortcutText.endSuccess)
        case .saveFailed:
            if let notice = appModel.rideController.notice {
                return .result(dialog: "\(RideShortcutText.saveFailedPrefix)\(notice.message)")
            }
            return .result(dialog: RideShortcutText.saveFailed)
        case .finishing:
            return .result(dialog: RideShortcutText.endInProgress)
        case .recording, .requestingAuthorization, .starting:
            return .result(dialog: RideShortcutText.endInProgress)
        }
    }
}

struct RideShortcutsProvider: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .teal

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRideIntent(),
            phrases: [
                "在\(.applicationName)开始骑行",
                "用\(.applicationName)开始骑行",
                "\(.applicationName)开始骑行",
                "打开\(.applicationName)开始骑行",
                "在\(.applicationName)记录骑行",
                "用\(.applicationName)记录骑行"
            ],
            shortTitle: "开始骑行",
            systemImageName: "figure.outdoor.cycle"
        )

        AppShortcut(
            intent: EndRideIntent(),
            phrases: [
                "在\(.applicationName)结束骑行",
                "用\(.applicationName)结束骑行",
                "\(.applicationName)结束骑行",
                "在\(.applicationName)停止骑行",
                "用\(.applicationName)停止骑行",
                "\(.applicationName)停止骑行"
            ],
            shortTitle: "结束骑行",
            systemImageName: "stop.circle"
        )
    }
}
