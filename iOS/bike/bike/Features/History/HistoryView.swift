import SwiftUI

struct HistoryView: View {
    let library: RideLibrary
    let startFirstRide: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if library.rides.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(library.rides) { ride in
                                NavigationLink(value: ride) {
                                    HistoryRideCard(ride: ride)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(AppTheme.pageBackground.ignoresSafeArea())
            .navigationTitle("历史")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(AppTheme.pageBackground, for: .navigationBar)
            .overlay(alignment: .top) {
                if let error = library.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(AppTheme.destructive, in: Capsule())
                        .padding(.top, 8)
                }
            }
            .navigationDestination(for: RideRecord.self) { ride in
                RideDetailView(ride: ride)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有骑行记录", systemImage: "bicycle")
                .foregroundStyle(.white)
        } description: {
            Text("前往骑行页面，开始记录第一次骑行。")
                .foregroundStyle(AppTheme.secondary)
        } actions: {
            Button("开始骑行", action: startFirstRide)
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .foregroundStyle(.black)
                .accessibilityLabel("前往骑行页面")
        }
    }
}

private struct HistoryRideCard: View {
    let ride: RideRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    value("骑行日期", RideFormatting.date(ride.startDate))
                    value("开始时间", RideFormatting.time(ride.startDate))
                }
                HStack {
                    value("总距离", RideFormatting.distance(ride.distanceMeters))
                    value("全程时间", RideFormatting.fullDuration(ride.totalElapsedSeconds))
                    value("全程速度", RideFormatting.speed(ride.overallSpeedMetersPerSecond))
                }
                HStack {
                    value("运动时间", RideFormatting.fullDuration(ride.movingElapsedSeconds))
                    value("平均速度", RideFormatting.speed(ride.averageSpeedMetersPerSecond))
                }
            }
            Image(systemName: "chevron.right")
                .foregroundStyle(AppTheme.accent)
                .frame(width: AppTheme.minimumTapSize, height: AppTheme.minimumTapSize)
        }
        .padding(16)
        .foregroundStyle(.white)
        .background(AppTheme.panelBackground, in: RoundedRectangle(cornerRadius: 18))
    }

    private func value(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(AppTheme.secondary)
            Text(text).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
