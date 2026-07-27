//
//  ContentView.swift
//  bike
//
//  Created by chenchi on 2026/7/19.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppearancePreference.storageKey) private var appearancePreference = AppearancePreference.system

    var body: some View {
        @Bindable var appModel = appModel

        TabView(selection: $appModel.selectedTab) {
            RideView(
                controller: appModel.rideController,
                isOffline: appModel.networkMonitor.isOffline
            )
            .tabItem { Label("骑行", systemImage: "bicycle") }
            .tag(AppTab.ride)

            HistoryView(library: appModel.rideLibrary) {
                appModel.selectedTab = .ride
            }
            .tabItem { Label("历史", systemImage: "chart.bar.fill") }
            .tag(AppTab.history)

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .tint(AppTheme.accentForeground)
        .toolbarBackground(AppTheme.pageBackground, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .preferredColorScheme(appearancePreference.preferredColorScheme)
        .task { await appModel.start() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                appModel.rideController.appDidEnterBackground()
            case .active:
                appModel.rideController.appWillEnterForeground()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .alert(
            "上次骑行未正常结束",
            isPresented: $appModel.showInterruptedRideAlert
        ) {
            Button("确认并删除", role: .destructive) {
                Task { await appModel.discardInterruptedRide() }
            }
        } message: {
            Text(appModel.interruptedRideError ?? "上次骑行未正常结束，记录未保存。确认后将删除临时记录。")
        }
    }
}
