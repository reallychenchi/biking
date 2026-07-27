import SwiftUI

struct SettingsView: View {
    @AppStorage(AppearancePreference.storageKey) private var appearancePreference = AppearancePreference.system

    var body: some View {
        NavigationStack {
            List {
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
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.pageBackground, for: .navigationBar)
        }
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
