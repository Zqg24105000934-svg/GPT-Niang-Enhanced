import SwiftUI
import AppKit
import GPTNiangCore

// Coordinates, colors and timing are taken from widget.xaml/widget.ps1 (v1.2.5).
struct WidgetView: View {
    @ObservedObject var model: WidgetModel
    let onDrag: (CGSize) -> Void
    let onSettings: () -> Void
    let onContextMenu: (NSEvent, NSView) -> Void
    var onRelease: (CGPoint) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false
    @State private var near: Double = 0
    @State private var tail: Double = 0
    @State private var cloud: Double = 0
    @State private var text: Double = 0
    @State private var displayedMessage: String?
    @State private var animationGeneration = 0
    @State private var sceneGeneration = 0
    @State private var hovering = false
    @State private var frozenPhase: Double = 0
    @State private var bubblePresented = false
    @State private var dragging = false
    @State private var dragStarted = Date.distantPast
    @State private var dragReleased = Date.distantPast
    @State private var dragSway = 0.0
    @State private var previousDrag = CGSize.zero
    private let ink = Color(hex: "745A98")
    private let ease = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.2)
    private let rebound = Animation.timingCurve(0.34, 1.56, 0.64, 1, duration: 0.22)

    var body: some View {
        TimelineView(.animation(minimumInterval: timelineInterval, paused: !model.visualsActive || !needsTimeline)) { context in
            let phase = model.colorPaused || reduceMotion ? frozenPhase : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.6) / 2.6
            stage(date: context.date, phase: phase)
        }
        .frame(width: model.canvasSize.width * model.displayScale, height: model.canvasSize.height * model.displayScale, alignment: .topLeading)
        .environment(\.colorScheme, .light)
        .onAppear { animateBubble(model.bubble); displayedMessage = model.message }
        .onChange(of: model.colorPaused) { paused in
            if paused { frozenPhase = Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.6) / 2.6 }
        }
        .onChange(of: reduceMotion) { value in
            if value { frozenPhase = Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.6) / 2.6 }
        }
        .onChange(of: model.bubble) { animateBubble($0) }
        .onChange(of: model.visualsActive) { active in
            if !active { dragging = false; pressed = false; previousDrag = .zero; dragReleased = .distantPast }
        }
        .onChange(of: model.message) { next in
            sceneGeneration += 1
            let generation = sceneGeneration
            if !model.bubble || reduceMotion { displayedMessage = next; return }
            withAnimation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.12)) { text = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                guard generation == sceneGeneration, model.bubble else { return }
                displayedMessage = next
                withAnimation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.16)) { text = 1 }
            }
        }
        .contextMenu {
            Button(model.text("查看額度")) { model.toggleQuota() }
            Button(model.text("刷新額度")) { model.refresh() }
            Button(model.text("來一句語錄")) { model.showQuote() }
            Divider()
            Toggle(model.text("回答结束提醒"), isOn: Binding(get: { model.completionEnabled }, set: { model.completionEnabled = $0; model.savePreferences() }))
            WidgetAudioMenu(audio: model.audio)
            Button(model.text("設定…"), action: onSettings)
            Button(model.text("退出 GPT 娘")) { NSApp.terminate(nil) }
        }
    }
    private var needsTimeline: Bool {
        model.bubble || (!reduceMotion && (dragging || Date().timeIntervalSince(dragReleased) < 1 || model.petReaction != nil || model.enhancements.idleMotion || (model.colorScope != .none && !model.colorPaused) || Date().timeIntervalSince(model.hopStarted) < 1))
    }
    private var timelineInterval: Double {
        if model.characterRig != nil {
            let moving = !reduceMotion && (dragging || Date().timeIntervalSince(dragReleased) < 1 || model.petReaction != nil || model.enhancements.idleMotion || Date().timeIntervalSince(model.hopStarted) < 1)
            return PetRigMotion.frameInterval(performance: model.effectivePerformance, moving: moving)
        }
        if !reduceMotion, let reaction = model.petReaction {
            return model.effectivePerformance.frameInterval(active: reaction.kind != .nap)
        }
        if !reduceMotion && Date().timeIntervalSince(model.hopStarted) < 1 { return model.effectivePerformance.frameInterval(active: true) }
        if reduceMotion || (!model.enhancements.idleMotion && (model.colorScope == .none || model.colorPaused)) { return 1 }
        return model.effectivePerformance.frameInterval(active: hovering || pressed || Date().timeIntervalSince(model.hopStarted) < 1)
    }
    private func stage(date: Date, phase: Double) -> some View {
        let mirrored = model.facingLeft
        let fullBody = model.enhancements.fullBody
        let motion = !reduceMotion && model.visualsActive
        let idle = motion && model.enhancements.idleMotion
        let t = date.timeIntervalSinceReferenceDate
        let breath = idle ? sin(t * 1.5) : 0
        let hopAge = max(0, date.timeIntervalSince(model.hopStarted))
        let hop = motion && hopAge < 0.65 ? sin(hopAge / 0.65 * .pi) * 14 : 0
        let lean = idle && model.enhancements.edgePeek ? sin(t * 0.65) * 1.4 : 0
        let characterHeight: Double = fullBody ? 320 : 208
        let pose = model.petReaction?.pose(at: t,
            pointerX: (model.playPointer?.x ?? 0.5) * 2 - 1,
            pointerY: (model.playPointer?.y ?? 0.5) * 2 - 1,
            reducedMotion: !motion) ?? PetReactionPose()
        let rig = model.characterRig
        let rigPose = PetRigMotion.sample(time: t, idle: idle, expressiveIdle: model.enhancements.edgePeek, reaction: model.petReaction,
            pointerX: (model.playPointer?.x ?? 0.5) * 2 - 1, pointerY: (model.playPointer?.y ?? 0.5) * 2 - 1,
            dragging: dragging, dragAge: date.timeIntervalSince(dragStarted), dragSway: dragSway,
            releaseAge: date.timeIntervalSince(dragReleased), reducedMotion: !motion)
        return ZStack(alignment: .topLeading) {
            // Do not reformat quota dates/text on every animation frame while
            // the bubble is invisible. Keep it only until its closing fade ends.
            if bubblePresented {
            OriginalBubbleShape().fill(style("surface", phase: phase))
                .overlay(OriginalBubbleShape().stroke(style("accent", phase: phase), lineWidth: 4))
                .frame(width: 350, height: 239)
                .scaleEffect(0.7 + 0.3 * cloud, anchor: UnitPoint(x: 0.4425, y: 0.36)).opacity(cloud)
                .contentShape(OriginalBubbleShape()).onTapGesture { model.clickBubble() }
                .allowsHitTesting(model.bubble)
            Ellipse().fill(style("surface", phase: phase)).overlay(Ellipse().stroke(style("accent", phase: phase), lineWidth: 4))
                .frame(width: 25, height: 18).scaleEffect(0.7 + 0.3 * tail).opacity(tail)
                .offset(x: 108, y: 182).onTapGesture { model.clickBubble() }.allowsHitTesting(model.bubble)
            Ellipse().fill(style("surface", phase: phase)).overlay(Ellipse().stroke(style("accent", phase: phase), lineWidth: 4))
                .frame(width: 17, height: 12).scaleEffect(0.7 + 0.3 * near).opacity(near)
                .offset(x: 142, y: 214).onTapGesture { model.clickBubble() }.allowsHitTesting(model.bubble)
            scene(now: date, phase: phase)
                .frame(width: displayedMessage == nil ? 184 : 218, height: displayedMessage == nil ? 115 : 126)
                .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                .opacity(text).offset(x: displayedMessage == nil ? 63 : 46, y: displayedMessage == nil ? 22 : 22)
                .allowsHitTesting(model.bubble).contentShape(Rectangle()).onTapGesture { model.clickBubble() }
            if model.bubble && displayedMessage == nil {
                Button { model.refresh(renewBubble: true) } label: { Image(systemName: model.refreshing ? "hourglass" : "arrow.clockwise").font(.system(size: 12)).foregroundStyle(style("ink", phase: phase)) }
                    .buttonStyle(.plain).disabled(model.refreshing).frame(width: 20, height: 20)
                    .scaleEffect(x: mirrored ? -1 : 1, y: 1).opacity(text).offset(x: 184, y: 20)
                    .help(model.text("立即刷新額度")).accessibilityLabel(model.text("刷新額度"))
            }
            }
            if let image = model.characterImage {
                let girl = Group {
                    if let rig { PetRigView(assets: rig, pose: rigPose) }
                    else { Image(nsImage: image).resizable().interpolation(.high).scaledToFit() }
                }.frame(width: 208, height: characterHeight)
                ZStack {
                    if model.colorScope == .full { Rectangle().fill(style("accent", phase: phase)).mask(girl).opacity(0.62).blur(radius: 7) }
                    girl
                    if model.colorScope == .full { Rectangle().fill(style("accent", phase: phase)).mask(girl).opacity(0.34).allowsHitTesting(false) }
                }
                .frame(width: 208, height: characterHeight).contentShape(Rectangle())
                .scaleEffect(x: rig == nil ? (pressed ? 1.04 : 1) * pose.scaleX : 1,
                             y: rig == nil ? (pressed ? 0.94 : 1 + breath * 0.006) * pose.scaleY : 1, anchor: .bottom)
                .rotationEffect(.degrees(rig == nil ? pose.rotation + (pressed ? 0 : (hovering && motion && model.petReaction == nil ? -2 : lean)) : 0), anchor: .bottom)
                .offset(x: rig == nil ? pose.x : 0, y: (rig == nil ? pose.y - (idle ? (breath + 1) * 0.6 : 0) : 0) - hop)
                .overlay(CharacterInteraction(onPress: { down in
                    model.interactionActive = down
                    withAnimation(reduceMotion ? nil : rebound) { pressed = down }
                    model.play(down ? "press" : "release")
                }, onDrag: { translation in
                    if translation == .zero {
                        if dragging { dragReleased = Date() }
                        dragging = false; previousDrag = .zero
                    } else {
                        if !dragging { dragStarted = Date(); model.stopPetInteraction() }
                        dragging = true
                        let direction = min(1, max(-1, (translation.width - previousDrag.width) / 12))
                        dragSway = dragSway * 0.65 + direction * 0.35
                        previousDrag = translation
                    }
                    onDrag(translation)
                    if translation == .zero { model.savePreferences() }
                }, onClick: { model.characterClick() }, onMenu: onContextMenu,
                    locked: model.enhancements.positionLocked, onRelease: onRelease,
                    onDoubleClick: { model.interact(.cuddle) }, onPet: { model.interact(.pet) },
                    onPointer: { model.trackPlayPointer($0) },
                    tracksPlayPointer: model.petReaction?.kind == .play && model.visualsActive,
                    pointerInterval: model.effectivePerformance.frameInterval(active: true)))
                .onHover { value in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { hovering = value }
                    model.hovering = value
                }.offset(x: 142, y: 142)
                .accessibilityElement().accessibilityLabel("GPT 娘：单击查看额度，双击撒娇，长按头部摸摸头，拖动调整位置")
                .accessibilityAddTraits(.isButton).accessibilityAction { model.characterClick() }
            }
            reactionOverlay(date: date, characterHeight: characterHeight).allowsHitTesting(false)
            Menu {
                ForEach(PetReaction.allCases, id: \.self) { reaction in
                    Button(reaction.title) { model.interact(reaction) }
                }
                Divider()
                Button("停止互动") { model.stopPetInteraction() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "hand.tap").font(.system(size: 11))
                    Text("互动").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(ink).padding(.horizontal, 10).padding(.vertical, 7)
                .background(Color.white.opacity(0.96), in: Capsule())
                .overlay(Capsule().stroke(Color(hex: "DACCEB"), lineWidth: 1))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .scaleEffect(x: mirrored ? -1 : 1, y: 1).offset(x: 282, y: 108)
            .accessibilityLabel("互动，点按打开")
            .help("点按选择互动；不需要右键")
            if hovering && !model.hideMenu {
                Button(action: onSettings) { Image(systemName: "line.3.horizontal").font(.system(size: 15)).foregroundStyle(ink).frame(width: 24, height: 24).background(Color(hex: "EDE7F6"), in: RoundedRectangle(cornerRadius: 6)) }
                    .buttonStyle(.plain).scaleEffect(x: mirrored ? -1 : 1, y: 1).offset(x: 320, y: 162)
                    .help(model.text("掛件設定")).accessibilityLabel(model.text("掛件設定"))
            }
        }
        .frame(width: 350, height: fullBody ? 462 : 350, alignment: .topLeading)
        .scaleEffect(x: mirrored ? -1 : 1, y: 1, anchor: .bottom)
        .padding(14).scaleEffect(model.displayScale, anchor: .topLeading)
    }
    @ViewBuilder private func reactionOverlay(date: Date, characterHeight: Double) -> some View {
        if let reaction = model.petReaction {
            let age = reaction.age(at: date.timeIntervalSinceReferenceDate)
            let progress = reaction.progress(at: date.timeIntervalSinceReferenceDate)
            let still = reduceMotion || !model.visualsActive
            let tint = Color(hex: reaction.kind == .snack ? "BD8A51" : "AA77AA")
            HStack(spacing: 4) {
                Image(systemName: reaction.kind.symbol).font(.system(size: 10))
                Text(reaction.kind.mood).font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 9).padding(.vertical, 5)
            .foregroundStyle(Color(hex: "745A98"))
            .background(.white.opacity(0.94), in: Capsule())
            .overlay(Capsule().stroke(Color(hex: "DACCEB"), lineWidth: 1))
            .scaleEffect(x: model.facingLeft ? -1 : 1, y: 1)
            .offset(x: reaction.kind == .nap ? 196 : 248, y: 144)
            if reaction.kind == .play, let pointer = model.playPointer {
                Image(systemName: "sparkle").font(.system(size: 23)).foregroundStyle(tint)
                    .rotationEffect(.degrees(still ? 0 : age * 70))
                    .position(x: 142 + pointer.x * 208, y: 142 + pointer.y * characterHeight)
                    .accessibilityHidden(true)
            } else {
                ForEach(0..<3) { index in
                    let phase = (age * 0.65 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                    Image(systemName: reaction.kind == .nap ? "z.circle" : reaction.kind.symbol)
                        .font(.system(size: 14 + Double(index) * 2, weight: .medium))
                        .foregroundStyle(tint)
                        .opacity(still ? 0.8 : max(0, sin(phase * .pi)) * min(1, (1 - progress) * 5))
                        .offset(x: index == 1 ? 326 : 146 + Double(index) * 8,
                                y: 208 + Double(index) * 22 - (still ? 0 : phase * 46))
                        .accessibilityHidden(true)
                }
            }
        }
    }
    private func scene(now: Date, phase: Double) -> some View {
        Group {
            if let quote = displayedMessage {
                if model.isCompletionMessage {
                    VStack(spacing: 0) { Text("Codex"); Text(model.text("有回复已结束")) }.font(.system(size: 30, weight: .bold)).lineLimit(1).fixedSize().foregroundStyle(ink)
                } else {
                Text(quote).font(.system(size: 24, weight: .bold)).multilineTextAlignment(.center)
                    .minimumScaleFactor(0.3).lineLimit(6).padding(.horizontal, 12)
                    .foregroundStyle(model.colorScope == .none ? AnyShapeStyle(ink) : style("ink", phase: phase))
                    .help(quote)
                }
            } else {
                VStack(spacing: 2) {
                    Text(quotaTitle(now: now)).font(.system(size: 12, weight: .semibold)).foregroundStyle(style("ink", phase: phase))
                        .help(quotaDetails(now: now))
                    if model.snapshot.displayWindows.isEmpty {
                        Text(model.snapshot.error ?? model.text("目前帳戶未提供額度視窗"))
                            .font(.system(size: 12)).foregroundStyle(Color(hex: "7D6B91")).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(model.snapshot.displayWindows) { window in
                            VStack(spacing: 1) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(window.title(language: model.language)).font(.system(size: 13))
                                        Text(model.text(window.expired(at: now) ? "上次 %@%%" : "已用 %@%%", String(format: "%.1f", 100-window.remaining).replacingOccurrences(of: ".0", with: "")))
                                            .font(.system(size: 9))
                                    }.foregroundStyle(Color(hex: "76638D"))
                                    Spacer()
                                    Text(window.expired(at: now) ? "—" : "\(window.percentageText)%")
                                        .font(.system(size: 24, weight: .bold)).monospacedDigit()
                                        .foregroundStyle(quotaStyle(window, now: now, phase: phase))
                                }.frame(height: 25)
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color(hex: "EAE4F3"))
                                        Capsule().fill(quotaStyle(window, now: now, phase: phase))
                                            .frame(width: geometry.size.width * (window.expired(at: now) ? 0 : max(0, min(1, window.remaining / 100))))
                                    }
                                }.frame(height: 4)
                                Text(window.resetText(at: now, countdown: now.timeIntervalSince(model.sceneStarted) < 2, language: model.language))
                                    .font(.system(size: 11)).foregroundStyle(Color(hex: "7D6B91"))
                                    .frame(maxWidth: .infinity, alignment: .leading).lineLimit(1).minimumScaleFactor(0.85)
                            }
                        }
                        if model.snapshot.stale(at: now) {
                            Text(model.text("舊快照 · 刷新後確認")).font(.system(size: 9)).foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
    }
    private func quotaTitle(now: Date) -> String {
        if !model.snapshot.ok { return model.text("暂无法读取") }
        return model.snapshot.stale(at: now) ? model.text("上次剩余额度") : model.text("剩餘額度")
    }
    private func quotaDetails(now: Date) -> String {
        var rows = [model.text("目前方案：%@", model.snapshot.planLabel ?? model.text("未知套餐"))]
        for window in model.snapshot.validWindows {
            rows.append("\(window.title(language: model.language))：\(window.percentageText)% · \(window.resetText(at: now, language: model.language))")
            if window.isIndividual {
                rows.append(model.text("个人额度，非公司总余额"))
                if let total = window.total, let used = window.amountUsed, total.isFinite, used.isFinite {
                    rows.append(model.text("已用 %@ / %@", String(used), String(total)))
                }
            }
        }
        if let at = model.snapshot.observedAt, at.isFinite {
            rows.append(model.text("更新时间：%@", Date(timeIntervalSince1970: at/1000).formatted(date: .abbreviated, time: .standard)))
        }
        if let error = model.snapshot.error { rows.append(error) }
        return rows.joined(separator: "\n")
    }
    private func quotaStyle(_ window: QuotaWindow, now: Date, phase: Double) -> AnyShapeStyle {
        if window.expired(at: now) { return AnyShapeStyle(Color(hex: "95889F")) }
        if window.remaining <= 10 { return AnyShapeStyle(Color(hex: "B74839")) }
        if window.remaining <= 25 { return AnyShapeStyle(Color(hex: "A06C1C")) }
        return model.colorScope == .full ? style("ink", phase: phase) : AnyShapeStyle(ink)
    }
    private func style(_ role: String, phase: Double) -> AnyShapeStyle {
        guard model.colorScope == .full || (model.colorScope == .text && role == "ink") else {
            return AnyShapeStyle(role == "surface" ? Color.white : ink)
        }
        let colors = Appearance.palette(for: model.message ?? "", rainbow: model.colorMode == .rainbow || model.message == nil)
        let loop = Array(colors.dropLast())
        let repeated = loop + loop + loop + [colors.last!]
        let stops = repeated.enumerated().map { index, hex in Gradient.Stop(color: Color(hex: hex, role: role), location: Double(index) / Double(repeated.count - 1)) }
        return AnyShapeStyle(LinearGradient(gradient: Gradient(stops: stops), startPoint: UnitPoint(x: -1 - phase, y: 0.5), endPoint: UnitPoint(x: 2 - phase, y: 0.5)))
    }
    private func animateBubble(_ opening: Bool) {
        animationGeneration += 1; sceneGeneration += 1
        let generation = animationGeneration
        if opening { bubblePresented = true }
        if reduceMotion { bubblePresented = opening; near = opening ? 1 : 0; tail = near; cloud = near; text = near; return }
        if opening {
            displayedMessage = model.message
            near = 0; tail = 0; cloud = 0; text = 0
            for (delay, part) in [(0.0, 0), (0.13, 1), (0.26, 2), (0.36, 3)] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    guard generation == animationGeneration, model.bubble else { return }
                    withAnimation(part == 3 ? .timingCurve(0.25, 0.1, 0.25, 1, duration: 0.16) : ease) {
                        switch part { case 0: near = 1; case 1: tail = 1; case 2: cloud = 1; default: text = 1 }
                    }
                }
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                guard generation == animationGeneration, !model.bubble else { return }
                bubblePresented = false
            }
            withAnimation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.16)) { text = 0 }
            for (delay, part) in [(0.1, 2), (0.2, 1), (0.3, 0)] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    guard generation == animationGeneration, !model.bubble else { return }
                    withAnimation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.18)) {
                        switch part { case 0: near = 0; case 1: tail = 0; default: cloud = 0 }
                    }
                }
            }
        }
    }
}

private extension Color {
    init(hex: String, role: String = "accent") {
        let value = UInt64(hex, radix: 16) ?? 0
        var components = [Double((value >> 16) & 255), Double((value >> 8) & 255), Double(value & 255)].map { $0 / 255 }
        let other = role == "surface" ? [1.0, 1, 1] : [39.0 / 255, 25.0 / 255, 56.0 / 255]
        let amount = role == "surface" ? 0.92 : role == "ink" ? 0.44 : 0
        for index in 0..<3 { components[index] = components[index] * (1 - amount) + other[index] * amount }
        self.init(red: components[0], green: components[1], blue: components[2])
    }
}
