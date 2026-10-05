import Foundation
import SwiftUI

enum BuildChannel {
    static func isTest(info: [String: Any]) -> Bool { info["AxiosBuildChannel"] as? String == "test" }
    static var isTest: Bool { isTest(info: Bundle.main.infoDictionary ?? [:]) }
    static var bundleIdentifier: String { isTest ? "com.axiosnotch.app.test" : "com.axiosnotch.app" }
}

struct TestBuildBadge: View {
    var body: some View {
        Label("BUILD DE TESTE", systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(.black)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Color.yellow, in: RoundedRectangle(cornerRadius: 4))
            .help(tr("Homologação interna — testes pendentes", "Internal acceptance build — testing pending"))
            .accessibilityLabel(tr("Build de teste, pendente de homologação", "Test build, acceptance pending"))
    }
}
