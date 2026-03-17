import SwiftUI
import OfflineAgentCore

struct RootView: View {
    @StateObject private var vm: ChatViewModel

    init() {
        let paths = (try? AppPaths.default()) ?? AppPaths(rootURL: URL(fileURLWithPath: NSTemporaryDirectory()))
        let logger = LocalLogger(url: paths.logURL)
        let wiper = DataWiper(paths: paths)
        let inference = InferenceService(backend: MockInferenceBackend())
        _vm = StateObject(wrappedValue: ChatViewModel(inference: inference, logger: logger, wiper: wiper))
    }

    var body: some View {
        ChatScreen(vm: vm)
    }
}

