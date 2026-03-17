import SwiftUI
import OfflineAgentCore

struct ChatScreen: View {
    @ObservedObject var vm: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            TopBar(
                mode: vm.mode,
                isSpeakerOn: vm.isSpeakerOn,
                isBellOn: vm.isBellOn,
                onToggleMode: { vm.toggleMode() },
                onToggleSpeaker: { vm.isSpeakerOn.toggle() },
                onToggleBell: { vm.isBellOn.toggle() }
            )
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(vm.messages) { msg in
                            MessageBubble(message: msg, mode: vm.mode)
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .onChange(of: vm.messages.count) { _ in
                    guard let last = vm.messages.last else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider()

            ZStack(alignment: .bottom) {
                if vm.isCommandPaletteVisible {
                    CommandPalette(
                        items: vm.commandPaletteItems,
                        onSelect: { item in vm.applyCommandPaletteItem(item) }
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                InputBar(
                    text: $vm.inputText,
                    onSend: { vm.sendCurrentText() },
                    onCancel: { vm.cancelGeneration() }
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
        .background(vm.mode == .work ? Color.white : Color(red: 0.98, green: 0.96, blue: 0.96))
        .sheet(isPresented: $vm.isSettingsPresented) {
            SettingsSheet(
                activeFrequency: vm.activeFrequency,
                selectedQuantization: vm.selectedQuantization,
                onClose: { vm.isSettingsPresented = false }
            )
        }
    }
}

private struct CommandPalette: View {
    let items: [CommandPaletteItem]
    let onSelect: (CommandPaletteItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                Button {
                    onSelect(item)
                } label: {
                    HStack {
                        Text(item.title)
                            .font(.system(size: 14, weight: .semibold))
                        Spacer(minLength: 0)
                        Text(item.command)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.gray)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                if item.id != items.last?.id {
                    Divider().opacity(0.4)
                }
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .accessibilityLabel("快捷指令")
    }
}

private struct SettingsSheet: View {
    let activeFrequency: String
    let selectedQuantization: String
    let onClose: () -> Void

    @State private var isSharePresented = false
    @State private var shareURL: URL?
    @State private var isWipeConfirmPresented = false

    var body: some View {
        NavigationView {
            List {
                Section("主动交互频率") {
                    Text(activeFrequency)
                }
                Section("量化版本") {
                    Text(selectedQuantization)
                }
                Section("日志") {
                    Button("导出本地日志") {
                        let paths = (try? AppPaths.default()) ?? AppPaths(rootURL: URL(fileURLWithPath: NSTemporaryDirectory()))
                        shareURL = paths.logURL
                        isSharePresented = true
                    }
                }
                Section("数据") {
                    Button(role: .destructive) {
                        isWipeConfirmPresented = true
                    } label: {
                        Text("一键清空所有数据（不可恢复）")
                    }
                }
                Section("说明") {
                    Text("所有数据仅在本地离线处理与加密存储。")
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("关闭", action: onClose)
                }
            }
            .sheet(isPresented: $isSharePresented) {
                if let shareURL {
                    ActivityView(items: [shareURL])
                } else {
                    ActivityView(items: [])
                }
            }
            .alert("确认清空？", isPresented: $isWipeConfirmPresented) {
                Button("取消", role: .cancel) {}
                Button("确认清空", role: .destructive) {
                    // 为避免在设置页直接执行破坏性操作，这里引导回到聊天页确认
                    onClose()
                }
            } message: {
                Text("请在聊天页回复“确认清空”以继续，或回复“取消”。")
            }
        }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct TopBar: View {
    let mode: ChatMode
    let isSpeakerOn: Bool
    let isBellOn: Bool
    let onToggleMode: () -> Void
    let onToggleSpeaker: () -> Void
    let onToggleBell: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleMode) {
                Text(mode == .work ? "工作" : "陪伴")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(mode == .work ? Color.white : Color(red: 0.96, green: 0.92, blue: 0.95))
                    .foregroundStyle(mode == .work ? Color.black : Color.black)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                VStack(spacing: 2) {
                    Text("本地离线")
                        .font(.system(size: 12, weight: .semibold))
                    Text("单模型本地运行｜数据加密存储")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.gray)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("本地离线，单模型本地运行，数据加密存储")

            Spacer(minLength: 0)

            HStack(spacing: 14) {
                Button(action: onToggleSpeaker) {
                    Image(systemName: isSpeakerOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isSpeakerOn ? Color.black : Color.gray)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSpeakerOn ? "关闭声音" : "开启声音")

                Button(action: onToggleBell) {
                    Image(systemName: isBellOn ? "bell.fill" : "bell.slash.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isBellOn ? Color.black : Color.gray)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isBellOn ? "关闭提醒" : "开启提醒")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct MessageBubble: View {
    let message: ChatMessage
    let mode: ChatMode

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 40)
            }

            Text(message.text)
                .font(.system(size: 16))
                .lineSpacing(mode == .work ? 3 : 5)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(background)
                .overlay(border)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
                .accessibilityLabel(message.role == .user ? "我说：\(message.text)" : "助手说：\(message.text)")

            if message.role == .assistant {
                Spacer(minLength: 40)
            }
        }
    }

    private var cornerRadius: CGFloat {
        mode == .work ? 6 : 12
    }

    private var background: some View {
        Group {
            if message.role == .user {
                Color.black.opacity(0.06)
            } else {
                if mode == .work {
                    Color.white
                } else {
                    LinearGradient(
                        colors: [
                            Color(red: 0.99, green: 0.95, blue: 0.96),
                            Color(red: 0.95, green: 0.97, blue: 0.99),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
        }
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(mode == .work ? Color.gray.opacity(0.18) : Color.clear, lineWidth: 1)
    }
}

private struct InputBar: View {
    @Binding var text: String
    let onSend: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                // 语音入口占位：后续接入本地录音+单模型ASR
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.black)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("语音输入")

            TextField("输入精准指令/对话", text: $text)
                .textFieldStyle(.plain)
                .lineLimit(1)
                .submitLabel(.send)
                .onSubmit(onSend)

            if !text.isEmpty {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.gray)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("取消生成")
            }

            Button(action: onSend) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.black)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("发送")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

