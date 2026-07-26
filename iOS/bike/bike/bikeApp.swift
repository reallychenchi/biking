//
//  bikeApp.swift
//  bike
//
//  Created by chenchi on 2026/7/19.
//

import SwiftUI
import SwiftData
import UMCommon
import UMAPM

@main
struct bikeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    private let sharedModelContainer: ModelContainer
    @State private var appModel: AppModel

    init() {
        let schema = Schema([RideEntity.self, TrackPointEntity.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            sharedModelContainer = container
            _appModel = State(
                initialValue: AppModel(
                    repository: SwiftDataRideRepository(modelContainer: container)
                )
            )
        } catch {
            fatalError("Could not create local ride storage: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
        }
        .modelContainer(sharedModelContainer)
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // 友盟统计SDK初始化
        // 友盟APM性能监控配置（必须在UMConfigure.initWithAppkey之前调用）
        let config = UMAPMConfig.default()
        config.crashAndBlockMonitorEnable = true
        config.launchMonitorEnable = true
        config.memMonitorEnable = true
        config.oomMonitorEnable = true
        config.networkEnable = true
        config.javaScriptBridgeEnable = true
        config.pageMonitorEnable = true
        config.logCollectEnable = true
        UMCrashConfigure.setAPMConfig(config)

        UMConfigure.initWithAppkey("6a65502fe88ae439bf3ab8ef", channel: "App Store")
        return true
    }
}
