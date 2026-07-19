import SwiftUI

struct HistoryView: View {
    let library: RideLibrary
    let startFirstRide: () -> Void

    @State private var expandedRideIDs: Set<UUID> = []

    var body: some View {
        NavigationStack {
            Group {
                if library.rides.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(library.rides) { ride in
                                HistoryRideCard(
                                    ride: ride,
                                    isExpanded: expandedRideIDs.contains(ride.id),
                                    toggle: { toggle(ride.id) }
                                )
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

    private func toggle(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedRideIDs.contains(id) {
                expandedRideIDs.remove(id)
            } else {
                expandedRideIDs.insert(id)
            }
        }
    }
}

private struct HistoryRideCard: View {
    let ride: RideRecord
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: toggle) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            value("骑行日期", RideFormatting.date(ride.startDate))
                            value("开始时间", RideFormatting.time(ride.startDate))
                        }
                        HStack {
                            value("总距离", RideFormatting.distance(ride.distanceMeters))
                            value("运动时间", RideFormatting.fullDuration(ride.elapsedSeconds))
                            value("平均速度", RideFormatting.speed(ride.averageSpeedMetersPerSecond))
                        }
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: AppTheme.minimumTapSize, height: AppTheme.minimumTapSize)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "收起骑行详情" : "展开骑行详情")

            if isExpanded {
                Divider().overlay(AppTheme.secondary.opacity(0.4))
                    .padding(.vertical, 14)
                VStack(spacing: 10) {
                    detail("最快速度", RideFormatting.speed(ride.maximumSpeedMetersPerSecond))
                    detail("平均速度", RideFormatting.speed(ride.averageSpeedMetersPerSecond))
                    detail("开始时间", RideFormatting.dateTime(ride.startDate))
                    detail("结束时间", ride.endDate.map { RideFormatting.dateTime($0) } ?? "—")
                    detail("运动时间", RideFormatting.fullDuration(ride.elapsedSeconds))
                    detail("总距离", RideFormatting.distance(ride.distanceMeters))
                }
            }
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
