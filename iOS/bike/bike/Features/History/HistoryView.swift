import OSLog
import SwiftUI

struct HistoryView: View {
    let library: RideLibrary
    let startFirstRide: () -> Void
    @State private var selectedRide: RideSummary?
    @State private var isRootTabBarHidden = false

    var body: some View {
        NavigationStack {
            Group {
                if library.rides.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(library.rides) { ride in
                            Button {
                                openRideDetail(ride)
                            } label: {
                                HistoryRideCard(ride: ride) {
                                    try await library.loadRide(id: ride.id).points
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    library.stageDelete(ride: ride)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                .tint(AppTheme.destructive)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(AppTheme.pageBackground.ignoresSafeArea())
            .navigationTitle("历史")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .overlay(alignment: .top) {
                if let error = library.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(AppTheme.destructiveForeground)
                        .padding(10)
                        .background(AppTheme.destructive, in: Capsule())
                        .padding(.top, 8)
                }
            }
            .overlay(alignment: .bottom) {
                if let message = library.undoBannerMessage {
                    UndoBanner(message: message) {
                        library.undoDelete()
                    }
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: library.undoBannerMessage)
            .navigationDestination(item: $selectedRide) { summary in
                RideDetailView(summary: summary) {
                    try await library.loadRide(id: summary.id)
                }
            }
        }
        .toolbar(isRootTabBarHidden ? .hidden : .visible, for: .tabBar)
        .onChange(of: selectedRide) { _, ride in
            if ride == nil {
                isRootTabBarHidden = false
            }
        }
    }

    private func openRideDetail(_ ride: RideSummary) {
        withTransaction(Transaction(animation: nil)) {
            isRootTabBarHidden = true
        }
        DispatchQueue.main.async {
            selectedRide = ride
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有骑行记录", systemImage: "bicycle")
                .foregroundStyle(AppTheme.primaryText)
        } description: {
            Text("前往骑行页面，开始记录第一次骑行。")
                .foregroundStyle(AppTheme.secondaryText)
        } actions: {
            Button("开始骑行", action: startFirstRide)
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primaryActionBackground)
                .foregroundStyle(AppTheme.primaryActionForeground)
                .accessibilityLabel("前往骑行页面")
        }
    }
}

private struct UndoBanner: View {
    let message: String
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppTheme.primaryText)
            Spacer()
            Button("撤销", action: undo)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentForeground)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.panelBackground, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }
}

private struct HistoryRideCard: View {
    private static let snapshotSize = CGSize(width: 92, height: 92)

    let ride: RideSummary
    let loadPoints: () async throws -> [TrackPoint]

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RideRouteThumbnail(
                ride: ride,
                size: Self.snapshotSize,
                loadPoints: loadPoints
            )

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    value("日期", RideFormatting.date(ride.startDate))
                    value("开始时间", RideFormatting.time(ride.startDate))
                }
                HStack(spacing: 8) {
                    value("总距离", RideFormatting.distance(ride.distanceMeters))
                    value("平均速度", RideFormatting.speed(ride.averageSpeedMetersPerSecond))
                }
            }

            Image(systemName: "chevron.right")
                .foregroundStyle(AppTheme.accentForeground)
                .frame(width: 20, height: AppTheme.minimumTapSize)
        }
        .padding(12)
        .foregroundStyle(AppTheme.primaryText)
        .background(AppTheme.panelBackground, in: RoundedRectangle(cornerRadius: 18))
    }

    private func value(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(AppTheme.secondaryText)
            Text(text).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RideRouteThumbnail: View {
    private struct TaskID: Hashable {
        let rideID: UUID
        let updatedAt: Date
        let appearance: AppAppearance
    }

    private enum LoadingState {
        case loading
        case loaded(UIImage)
        case liveMap([TrackPoint])
        case empty
        case failed
    }

    let ride: RideSummary
    let size: CGSize
    let loadPoints: () async throws -> [TrackPoint]
    @Environment(\.colorScheme) private var colorScheme
    @State private var loadingState = LoadingState.loading

    private var appearance: AppAppearance {
        AppAppearance(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.pageBackground)

            switch loadingState {
            case .loading:
                ProgressView()
                    .tint(AppTheme.accentForeground)
                    .accessibilityLabel("正在生成轨迹图")
            case let .loaded(image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            case let .liveMap(points):
                RideRouteView(points: points)
                    .allowsHitTesting(false)
            case .empty:
                Image(systemName: "map")
                    .foregroundStyle(AppTheme.secondaryText)
                    .accessibilityLabel("无轨迹数据")
            case .failed:
                Image(systemName: "map.fill")
                    .foregroundStyle(AppTheme.secondaryText)
                    .accessibilityLabel("轨迹读取失败")
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.separator.opacity(0.35), lineWidth: 1)
        }
        .task(id: TaskID(rideID: ride.id, updatedAt: ride.updatedAt, appearance: appearance)) {
            loadingState = .loading
            do {
                let rendering = try await RideRouteSnapshotRenderer.shared.rendering(
                    rideID: ride.id,
                    updatedAt: ride.updatedAt,
                    size: size,
                    appearance: appearance,
                    loadPoints: loadPoints
                )
                switch rendering {
                case let .image(image):
                    loadingState = .loaded(image)
                case let .liveMap(points):
                    loadingState = .liveMap(points)
                case .empty:
                    loadingState = .empty
                }
            } catch is CancellationError {
                return
            } catch {
                loadingState = .failed
                AppLog.history.error("Failed to load ride route thumbnail rideID=\(ride.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            }
        }
        .accessibilityElement(children: .contain)
    }
}
