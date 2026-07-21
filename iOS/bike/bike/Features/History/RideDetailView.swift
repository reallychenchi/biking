import SwiftUI

struct RideDetailView: View {
    let ride: RideRecord

    var body: some View {
        TabView {
            RideDetailInfoView(ride: ride)
                .tabItem { Label("详情", systemImage: "list.bullet") }
            RideRouteView(ride: ride)
                .tabItem { Label("轨迹", systemImage: "map") }
        }
        .navigationTitle(RideFormatting.date(ride.startDate))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(AppTheme.pageBackground, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
    }
}

private struct RideDetailInfoView: View {
    let ride: RideRecord

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                detail("最快速度", RideFormatting.speed(ride.maximumSpeedMetersPerSecond))
                detail("全程速度", RideFormatting.speed(ride.overallSpeedMetersPerSecond))
                detail("平均速度", RideFormatting.speed(ride.averageSpeedMetersPerSecond))
                detail("开始时间", RideFormatting.dateTime(ride.startDate))
                detail("结束时间", ride.endDate.map { RideFormatting.dateTime($0) } ?? "—")
                detail("全程时间", RideFormatting.fullDuration(ride.totalElapsedSeconds))
                detail("运动时间", RideFormatting.fullDuration(ride.movingElapsedSeconds))
                detail("总距离", RideFormatting.distance(ride.distanceMeters))
            }
            .padding(16)
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .foregroundStyle(.white)
    }

    private func detail(_ title: String, _ text: String) -> some View {
        HStack {
            Text(title).foregroundStyle(AppTheme.secondary)
            Spacer()
            Text(text).monospacedDigit()
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}
