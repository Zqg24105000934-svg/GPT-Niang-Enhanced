import SwiftUI
import ServiceManagement
import GPTNiangCore

struct SettingsView: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject var updater: NativeUpdater
    @State private var loginError: String?

    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.text("GPT 娘")).font(.system(size: 27, weight: .semibold, design: .rounded))
                Text("macOS · \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            Text(model.text("讓小龍娘陪你掌握 Codex 額度。")).foregroundStyle(.secondary)
            section1
            section2
            enhancementsSection
            playSection
            section3
            section4
            section5
            if let error = model.settingsError { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button(model.text("開啟資料目錄")) { NSWorkspace.shared.open(model.dataDirectory) }
                Spacer()
                Button(model.text("重設位置")) { model.resetPosition() }
                Button(model.text("刷新額度")) { model.refresh() }
            }
            Text(model.text("額度可見時每 60 秒更新。使用目前 Codex 登入，不建立聊天或呼叫模型。"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24) }.frame(width: 500, height: 700)
        .onChange(of: model.language) { _ in model.savePreferences() }
        .onChange(of: model.desktopTopmost) { _ in model.savePreferences() }
        .onChange(of: model.soundOn) { _ in model.audio.updateVolume(); model.savePreferences() }
        .onChange(of: model.hideMenu) { _ in model.savePreferences() }
        .onChange(of: model.completionEnabled) { _ in model.savePreferences() }
        .onChange(of: model.scale) { _ in model.savePreferences() }
        .onChange(of: model.volume) { _ in model.audio.updateVolume(); model.savePreferences() }
        .onChange(of: model.colorMode) { _ in model.updateAppearance(); model.savePreferences() }
        .onChange(of: model.fullChance) { _ in model.updateAppearance(); model.savePreferences() }
        .onChange(of: model.textChance) { _ in model.updateAppearance(); model.savePreferences() }
        .onChange(of: model.colorPaused) { _ in model.savePreferences() }
        .onChange(of: model.specialQuotes) { _ in model.updateAppearance(); model.savePreferences() }
        .onChange(of: model.bubbleTapAdvance) { _ in model.savePreferences() }
        .onChange(of: model.followCodex) { _ in model.savePreferences() }
        .onChange(of: model.enhancements) { _ in model.savePreferences() }
    }

    private var section1: some View {
        Group {
        if Bundle.main.object(forInfoDictionaryKey: "GPTNiangEnhanced") as? Bool == true {
            GroupBox("本地增强版") {
                Text("基于 1.3.5 独立构建。原版与设置保留；增强版不自动安装上游更新，以免覆盖新增功能。")
                    .font(.caption).foregroundStyle(.secondary).padding(10)
            }
        } else {
            GroupBox(model.text("版本與更新")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(model.text("目前版本 %@", String(describing: updater.currentVersion)))
                        Spacer()
                        if updater.busy { ProgressView().controlSize(.small) }
                        Button(model.text("檢查更新")) { updater.check(manual: true) }.disabled(updater.busy)
                    }
                    Toggle(model.text("自動檢查並安裝正式版"), isOn: $updater.automatic)
                    Text(updater.localizedStatus(model.language)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(model.text("下載後關閉此視窗，掛件空閒時才會替換應用。確認新版啟動後清理上一版與下載缓存；偏好和語錄保留。"))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(10)
            }
        }
        }
    }

    private var enhancementsSection: some View {
        GroupBox("全身 · 互动 · 性能") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("全身形象（关闭可回到原版半身）", isOn: $model.enhancements.fullBody)
                if model.enhancements.fullBody {
                    Picker("全身风格", selection: $model.enhancements.fullBodyStyle) {
                        ForEach(PetFullBodyStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                Toggle("分层灵动动画（关闭可回到上一版立绘）", isOn: $model.enhancements.articulatedMotion)
                    .disabled(!model.enhancements.fullBody)
                Toggle("眨眼、呼吸与待机小动作", isOn: $model.enhancements.idleMotion)
                Toggle("轻微探头与摇摆", isOn: $model.enhancements.edgePeek)
                Toggle("拖动释放后的惯性（桌面模式）", isOn: $model.enhancements.inertia)
                Toggle("锁定位置", isOn: $model.enhancements.positionLocked)
                Toggle("鼠标穿透", isOn: $model.enhancements.clickThrough)
                Text("鼠标穿透后，从菜单栏的爪印图标关闭，或点“恢复显示与操作”。不会拦截其他软件的鼠标。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("透明度")
                    Slider(value: $model.enhancements.opacity, in: 0.25...1, step: 0.05)
                    Text("\(Int(model.enhancements.opacity * 100))%").monospacedDigit().frame(width: 42)
                }
                Picker("性能模式", selection: $model.enhancements.performance) {
                    ForEach(PetPerformance.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Text("分层动画：省电 15、平衡 24、流畅 30 帧；隐藏/休眠停止动画，低电量时自动省电。单击角色查看额度，点“互动”选择动作。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("跳一下") { model.hop() }
                    Spacer()
                    Button("恢复显示与操作") { model.resetPosition(); model.enhancements.opacity = 1; model.savePreferences() }
                }
            }.padding(10)
        }
    }

    private var section2: some View {
            GroupBox(model.text("界面语言")) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker(model.text("界面语言"), selection: $model.language) {
                        ForEach(InterfaceLanguage.allCases, id: \.self) { Text(model.text($0.title)).tag($0) }
                    }
                }.padding(10)
            }
    }

    private var playSection: some View {
        GroupBox("陪她玩 · 本地互动") {
            VStack(alignment: .leading, spacing: 10) {
                Text("点角色上方的“互动”即可选择，不需要右键。也可双击角色撒娇，长按头部半秒摸摸头。单击仍查看额度，拖动仍调整位置。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(PetReaction.allCases, id: \.self) { reaction in
                        Button { model.interact(reaction) } label: {
                            Label(reaction.title, systemImage: reaction.symbol).frame(maxWidth: .infinity)
                        }
                    }
                    Button("停止互动") { model.stopPetInteraction() }
                }
                Text("逗逗她时，在角色周围移动鼠标，她会倾身追随小星星。小憩时单击唤醒。所有动作限时结束；只读取鼠标方位，不调用模型、不读取屏幕内容。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(10)
        }
    }

    private var section3: some View {
            GroupBox(model.text("外觀與顯示")) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        ForEach([0.8, 1.0, 1.4], id: \.self) { value in
                            Button("\(Int(value * 100))%") { model.scale = value }
                        }
                    }
                    Toggle(model.text("提示音"), isOn: $model.soundOn)
                    WidgetAudioMenu(audio: model.audio)
                    Toggle(model.text("隐藏设置按钮"), isOn: $model.hideMenu)
                    HStack { Text(model.text("角色大小")).frame(width: 70, alignment: .leading); Slider(value: $model.scale, in: 0.6...2.5, step: 0.1); Text("\(Int(model.scale * 100))% ").monospacedDigit().frame(width: 48) }
                    HStack { Text(model.text("提示音量")).frame(width: 70, alignment: .leading); Slider(value: $model.volume, in: 0...1); Text(model.volume == 0 ? model.text("靜音") : "\(Int(model.volume * 100))% ").frame(width: 48) }
                    Picker(model.text("显示与位置"), selection: $model.followCodex) {
                        Text(model.text("仅在 Codex 窗口内")).tag(true)
                        Text(model.text("整个桌面自由拖动")).tag(false)
                    }.pickerStyle(.radioGroup)
                    if !model.followCodex { Toggle(model.text("始终置顶"), isOn: $model.desktopTopmost) }
                    Text(model.text("關閉後，掛件會固定在桌面；開啟時，Codex 隱藏或最小化後掛件也會隱藏。"))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let note = model.trackingNote { Text(note).font(.caption).foregroundStyle(.orange) }
                    Toggle(model.text("回答结束提醒"), isOn: $model.completionEnabled)
                    Toggle(model.text("登入 Mac 時自動開啟"), isOn: $model.loginRequested)
                        .onChange(of: model.loginRequested) { value in
                            do {
                                if value { try SMAppService.mainApp.register() }
                                else { try SMAppService.mainApp.unregister() }
                                model.savePreferences()
                                loginError = nil
                                if SMAppService.mainApp.status == .requiresApproval { loginError = model.text("請在系統設定的「登入項目」允許 GPT 娘。") }
                            } catch { loginError = model.text("登入項目設定失敗：%@", String(describing: error.localizedDescription)) }
                        }
                    if let loginError { Text(loginError).font(.caption).foregroundStyle(.orange) }
                }.padding(10)
            }
    }

    private var section4: some View {
            GroupBox(model.text("原版流光效果")) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker(model.text("配色模式"), selection: $model.colorMode) {
                        ForEach(ColorMode.allCases, id: \.self) { Text(model.text($0.title)).tag($0) }
                    }
                    Toggle(model.text("暫停流光"), isOn: $model.colorPaused)
                    HStack { Text(model.text("全身變色機率")); Slider(value: $model.fullChance, in: 0...100); Text(String(format: "%.1f%%", model.fullChance)).frame(width: 55) }
                    HStack { Text(model.text("僅文字變色機率")); Slider(value: $model.textChance, in: 0...100); Text(String(format: "%.1f%%", model.textChance)).frame(width: 55) }
                    TextField(model.text("特殊語錄（以換行分隔）"), text: $model.specialQuotes)
                    Toggle(model.text("點角色時也切換語錄／收起氣泡"), isOn: $model.bubbleTapAdvance)
                }.padding(10)
            }
    }

    private var section5: some View {
            GroupBox(model.text("自訂語錄 · 每行一則")) {
                VStack(alignment: .leading, spacing: 10) {
                    TextEditor(text: $model.quoteText).font(.system(size: 13)).frame(height: 145)
                        .scrollContentBackground(.hidden).padding(4)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    HStack {
                        Button(model.text("還原內建語錄")) { model.resetQuotes() }
                        Spacer()
                        Button(model.text("儲存語錄")) { model.saveQuotes() }.buttonStyle(.borderedProminent)
                    }
                }.padding(10)
            }
    }
}
