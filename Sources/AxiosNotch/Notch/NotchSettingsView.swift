import AppKit
import SwiftUI

/// Preferences, shown inside the notch like every other panel.
struct NotchSettingsView: View {
    @ObservedObject var controller: NotchWindowController
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                IconButton(systemName: "chevron.left") { controller.showPicker() }
                    .accessibilityLabel("Voltar")
                Text("Ajustes")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                AppBadge()
            }

            // Two equal rows of two equal cards.
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    SettingsCard(title: "Geral") {
                        Toggle("Iniciar ao fazer login", isOn: $settings.launchAtLogin)
                        if let error = settings.loginError {
                            Caption(error, color: Color(red: 0.95, green: 0.45, blue: 0.4))
                        } else if !LoginItem.isBundled {
                            Caption("Fora de um .app: usa um LaunchAgent deste binário.")
                        }
                    }
                    SettingsCard(title: "Vibração") {
                        Toggle("Vibrar ao passar o mouse", isOn: $settings.hoverHaptic)
                        Picker("", selection: $settings.hapticStrength) {
                            ForEach(HapticStrength.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .disabled(!settings.hoverHaptic)
                    }
                }
                HStack(spacing: 10) {
                    SettingsCard(title: "Acessibilidade") {
                        Text("Reduzir movimento")
                        Picker("", selection: $settings.motion) {
                            ForEach(MotionPreference.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Caption("Troca saltos e molas por transições simples.")
                    }
                    SettingsCard(title: "Avisos e terminal") {
                        Toggle("Aviso de resposta pronta", isOn: $settings.finishBanner)
                        HStack {
                            Text("Duração")
                            Slider(value: $settings.bannerSeconds, in: 2...10, step: 0.5)
                                .disabled(!settings.finishBanner)
                            Text(String(format: "%.1f s", settings.bannerSeconds))
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(width: 40, alignment: .trailing)
                        }
                        Stepper(value: $settings.terminalFontSize, in: 10...20, step: 1) {
                            Text("Fonte do terminal: \(Int(settings.terminalFontSize)) pt")
                        }
                    }
                }
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(0.9))
        .toggleStyle(.switch)
        .tint(NotchTheme.claudeAccent)
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 6)
        .padding(.bottom, 14)
        .padding(.top, 4)
    }
}

/// Every card shares one size so the grid reads as a clean 2×2.
enum SettingsLayout {
    static let cardHeight: CGFloat = 138
    static let spacing: CGFloat = 10
}

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .frame(height: SettingsLayout.cardHeight)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(NotchTheme.tileFill)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(NotchTheme.hairline, lineWidth: 1))
        }
    }
}

private struct Caption: View {
    let text: String
    var color: Color = .white.opacity(0.4)
    init(_ text: String, color: Color = .white.opacity(0.4)) { self.text = text; self.color = color }

    var body: some View {
        Text(text).font(.system(size: 10)).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
    }
}

/// The app's mark and name, tiny, in the corner of the settings panel.
private struct AppBadge: View {
    private static let mark: NSImage? = {
        guard let url = AppResources.url(forResource: "AxiosMark", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        HStack(spacing: 5) {
            Group {
                if let mark = Self.mark {
                    Image(nsImage: mark).resizable().scaledToFit()
                } else {
                    Image(systemName: "asterisk")
                }
            }
            .frame(width: 12, height: 12)
            Text("Axios Notch")
                .font(.system(size: 10.5, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.45))
        .padding(.trailing, 6)
        .accessibilityElement(children: .combine)
    }
}
