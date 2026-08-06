import SwiftUI

struct SettingsView: View {
    let library: RideLibrary
    @AppStorage(AppearancePreference.storageKey) private var appearancePreference = AppearancePreference.system
    @State private var selectedRide: RideSummary?

    private var stats: RidePersonalStats {
        RidePersonalStats(rides: library.rides)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("骑行统计") {
                    PersonalDistanceRow(distanceMeters: stats.totalDistanceMeters)

                    PersonalRecordLink(
                        title: "总距离最长",
                        systemImage: "road.lanes",
                        ride: stats.longestDistanceRide,
                        value: { RideFormatting.distance($0.distanceMeters) },
                        selectedRide: $selectedRide
                    )

                    PersonalRecordLink(
                        title: "最快速度最快",
                        systemImage: "speedometer",
                        ride: stats.fastestMaximumSpeedRide,
                        value: { RideFormatting.speed($0.maximumSpeedMetersPerSecond) },
                        selectedRide: $selectedRide
                    )

                    PersonalRecordLink(
                        title: "平均速度最快",
                        systemImage: "gauge.with.dots.needle.bottom.50percent",
                        ride: stats.fastestAverageSpeedRide,
                        value: { RideFormatting.speed($0.averageSpeedMetersPerSecond) },
                        selectedRide: $selectedRide
                    )

                    PersonalRecordLink(
                        title: "全程速度最快",
                        systemImage: "timer",
                        ride: stats.fastestOverallSpeedRide,
                        value: { RideFormatting.speed($0.overallSpeedMetersPerSecond) },
                        selectedRide: $selectedRide
                    )
                }

                Section("外观") {
                    Picker("主题", selection: $appearancePreference) {
                        ForEach(AppearancePreference.allCases) { preference in
                            Text(preference.title).tag(preference)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("主题外观")
                }

                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("关于", systemImage: "info.circle.fill")
                    }
                    .accessibilityLabel("关于骑行")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground)
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.pageBackground, for: .navigationBar)
            .navigationDestination(item: $selectedRide) { summary in
                RideDetailView(summary: summary) {
                    try await library.loadRide(id: summary.id)
                }
            }
        }
    }
}

private struct PersonalDistanceRow: View {
    let distanceMeters: Double

    var body: some View {
        HStack {
            Label("累计里程", systemImage: "sum")
            Spacer()
            Text(RideFormatting.distance(distanceMeters))
                .font(.body.monospacedDigit())
                .foregroundStyle(AppTheme.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PersonalRecordLink: View {
    let title: String
    let systemImage: String
    let ride: RideSummary?
    let value: (RideSummary) -> String
    @Binding var selectedRide: RideSummary?

    var body: some View {
        Button {
            guard let ride else { return }
            selectedRide = ride
        } label: {
            HStack(spacing: 12) {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(recordValue)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(AppTheme.secondaryText)
                    if let ride {
                        Text(RideFormatting.date(ride.startDate))
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ride == nil ? AppTheme.secondaryText.opacity(0.35) : AppTheme.accentForeground)
                    .accessibilityHidden(true)
            }
        }
        .disabled(ride == nil)
        .accessibilityLabel(accessibilityLabel)
    }

    private var recordValue: String {
        guard let ride else { return "暂无" }
        return value(ride)
    }

    private var accessibilityLabel: String {
        guard let ride else { return "\(title)，暂无" }
        return "\(title)，\(recordValue)，\(RideFormatting.date(ride.startDate))"
    }
}

private struct AboutView: View {
    private var versionText: String {
        let dictionary = Bundle.main.infoDictionary
        let version = dictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = dictionary?["CFBundleVersion"] as? String ?? "—"
        return "版本 \(version)（\(build)）"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "bicycle")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(AppTheme.accentForeground)
                    .accessibilityHidden(true)
                Text("骑行")
                    .font(.largeTitle.bold())
                Text(versionText)
                    .foregroundStyle(AppTheme.secondaryText)

                VStack(alignment: .leading, spacing: 18) {
                    aboutRow(icon: "figure.outdoor.cycle", text: "记录每一次骑行")
                    aboutRow(icon: "internaldrive.fill", text: "骑行记录仅保存在本机")
                    aboutRow(icon: "location.fill", text: "定位用于记录骑行轨迹、距离和速度")
                }
                .padding(20)
                .background(AppTheme.panelBackground, in: RoundedRectangle(cornerRadius: 18))
                .padding(.top, 16)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .foregroundStyle(AppTheme.primaryText)
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func aboutRow(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(text)
    }
}
