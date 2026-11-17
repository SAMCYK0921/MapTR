//
//  HelpBoardView.swift
//  MTR Lift Guide
//
//  In-station mutual-aid board ("seeking for help" / "offering help").
//
//  Every open request floats as a bubble on the station board. Tapping a bubble
//  opens the details; double-tapping pops it (offer help) and opens a chat plus
//  a schematic card that pins down the requester's spot inside the station.
//

import SwiftUI

// MARK: - Board

struct HelpBoardView: View {
    @EnvironmentObject private var lang: Lang
    @EnvironmentObject private var help: HelpStore
    let station: Station
    @Binding var path: [Destination]

    @State private var showingRequestForm = false
    @State private var selectedRequest: HelpRequest?
    @State private var poppedIds: Set<UUID> = []

    private var openRequests: [HelpRequest] { help.requests(for: station.id) }
    private var resolvedCount: Int {
        help.requests(for: station.id, includeResolved: true).filter { $0.status != .open }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                board
                legend
                requestButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(heroBackground.ignoresSafeArea())
        .navigationTitle(Text(lang.t("車站互助", "Station help")))
        .navigationBarTitleDisplayMode(.inline)
        .task { help.refreshSamples(for: station, lang: lang) }
        .sheet(isPresented: $showingRequestForm) {
            RequestHelpSheet(station: station)
        }
        .sheet(item: $selectedRequest) { request in
            HelpDetailSheet(station: station, request: request) { exit in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    path.append(.route(station, exit, .lift))
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(Color.navPurple).frame(width: 8, height: 8)
                Text(lang.t("車站互助", "Station help"))
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color.navPurple)
                Spacer()
                Text("\(openRequests.count) \(lang.t("個求助", "open"))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(lang.t("\(station.zh) · 誰需要幫手？", "\(station.en) · Who needs a hand?"))
                .font(.system(size: 29, weight: .bold, design: .serif))
                .foregroundStyle(.primary)
            Text(lang.t("輕按泡泡看詳情，連按兩下把泡泡戳破並伸出援手。",
                        "Tap a bubble for details, double-tap to pop it and offer help."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 16)
    }

    // MARK: Bubble board

    private var board: some View {
        GeometryReader { geo in
            let items = openRequests
            ZStack {
                HelpStationBackdrop()

                if items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(Color.green)
                        Text(lang.t("暫時沒有人求助", "No one needs help right now"))
                            .font(.subheadline.weight(.semibold))
                        Text(lang.t("你可以先發布求助，或稍後再來看看。",
                                    "Post a request, or check back later."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, request in
                        HelpBubble(request: request,
                                   lang: lang,
                                   isPopping: poppedIds.contains(request.id),
                                   onOpen: { selectedRequest = request },
                                   onPop: { pop(request) })
                            .position(bubblePoint(index: index,
                                                  count: items.count,
                                                  in: geo.size,
                                                  seed: request.offsetSeed))
                    }
                }
            }
        }
        .frame(height: 380)
        .glassSurface(cornerRadius: 28)
        .shadow(color: .black.opacity(0.05), radius: 12, y: 5)
    }

    /// Lays bubbles out on a grid (2 columns up to 4 items, 3 beyond) with a
    /// bounded jitter, so they never overlap while still feeling scattered.
    private func bubblePoint(index: Int, count: Int, in size: CGSize, seed: Double) -> CGPoint {
        let safeCount = max(count, 1)
        let columns = safeCount <= 4 ? 2 : 3
        let rows = max(Int(ceil(Double(safeCount) / Double(columns))), 1)
        let col = index % columns
        let row = (index / columns) % rows

        let cellW = size.width / CGFloat(columns)
        let cellH = size.height / CGFloat(rows)

        // Keep the centre at least one bubble radius + float margin from the cell
        // edge, so two neighbouring bubbles can never touch.
        let bubbleHalf: CGFloat = 56
        let maxJX = max(cellW * 0.5 - bubbleHalf, 0)
        let maxJY = max(cellH * 0.5 - bubbleHalf, 0)
        let seedY = (seed * 7.31).truncatingRemainder(dividingBy: 1.0)

        let jx = (CGFloat(seed) - 0.5) * 2 * maxJX
        let jy = (CGFloat(seedY) - 0.5) * 2 * maxJY

        let centerX = (CGFloat(col) + 0.5) * cellW
        let centerY = (CGFloat(row) + 0.5) * cellH
        return CGPoint(x: centerX + jx, y: centerY + jy)
    }

    private func pop(_ request: HelpRequest) {
        guard !poppedIds.contains(request.id) else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
            poppedIds.insert(request.id)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            help.claim(request.id)
            selectedRequest = help.request(id: request.id) ?? request
            poppedIds.remove(request.id)
        }
    }

    // MARK: Legend

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(HelpKind.allCases) { kind in
                HStack(spacing: 4) {
                    Circle().fill(kind.tint).frame(width: 8, height: 8)
                    Text(lang.t(kind.shortZh, kind.shortEn))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if resolvedCount > 0 {
                Text(lang.t("已幫 \(resolvedCount) 人", "\(resolvedCount) helped"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.navPurple)
            }
        }
    }

    // MARK: Request button

    private var requestButton: some View {
        VStack(spacing: 10) {
            Button {
                showingRequestForm = true
            } label: {
                Label(lang.t("我需要幫助", "I need help"), systemImage: "hand.raised.fill")
            }
            .buttonStyle(PrimaryButtonStyle())

            Text(lang.t("求助只在此車站內顯示，完成後泡泡會自動消失。",
                        "Requests show for this station only and vanish once resolved."))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var heroBackground: some View {
        LinearGradient(colors: [.heroTop, .heroTop, .heroBottom],
                       startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Floating bubble

private struct HelpBubble: View {
    let request: HelpRequest
    let lang: Lang
    let isPopping: Bool
    let onOpen: () -> Void
    let onPop: () -> Void

    @State private var floating = false
    @State private var ripple = false
    @State private var burst = false

    private let size: CGFloat = 92

    var body: some View {
        ZStack {
            // Burst particles — tucked behind the bubble, revealed as it pops.
            ForEach(0..<12, id: \.self) { index in
                burstParticle(index)
            }

            // Expanding shock ring.
            Circle()
                .stroke(request.kind.tint.opacity(0.55), lineWidth: 2)
                .frame(width: size * (ripple ? 1.95 : 1),
                       height: size * (ripple ? 1.95 : 1))
                .opacity(ripple ? 0 : 0.8)

            // Main bubble — shrinks away when popped.
            Circle()
                .fill(
                    LinearGradient(colors: [request.kind.tint.opacity(0.95),
                                            request.kind.tint.opacity(0.72)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: size, height: size)
                .overlay {
                    VStack(spacing: 3) {
                        Image(systemName: request.kind.symbol)
                            .font(.system(size: 20, weight: .bold))
                        Text(lang.t(request.kind.shortZh, request.kind.shortEn))
                            .font(.caption2.weight(.bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(6)
                }
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.45), lineWidth: 1.5)
                }
                .shadow(color: request.kind.tint.opacity(0.45), radius: 12, y: 6)
                .scaleEffect(isPopping ? 0.05 : 1)
                .opacity(isPopping ? 0 : 1)
        }
        .offset(y: floating ? -7 : 7)
        .contentShape(Circle())
        .onTapGesture(count: 2) {
            Haptics.impact(.rigid)
            withAnimation(.easeOut(duration: 0.28)) { ripple = true }
            withAnimation(.easeOut(duration: 0.42)) { burst = true }
            onPop()
        }
        .onTapGesture {
            Haptics.tap()
            onOpen()
        }
        .onAppear {
            let delay = request.offsetSeed * 0.8
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true).delay(delay)) {
                floating = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(lang.t("\(request.requesterName)求助：\(request.kind.titleZh)",
                                        "\(request.requesterName) needs help: \(request.kind.titleEn)")))
        .accessibilityHint(Text(lang.t("連按兩下伸出援手", "Double-tap to offer help")))
    }

    /// One particle of the double-tap "burst": starts hidden at the centre, then
    /// flies outward while fading as the bubble pops.
    private func burstParticle(_ index: Int) -> some View {
        let count = 12
        let angle = Double(index) / Double(count) * 2 * Double.pi
        let distance = CGFloat(52 + (index % 4) * 9)
        let dot = CGFloat(6 + (index % 3) * 2)
        return Circle()
            .fill(index % 3 == 0 ? Color.white : request.kind.tint)
            .frame(width: dot, height: dot)
            .offset(x: burst ? CGFloat(cos(angle)) * distance : 0,
                    y: burst ? CGFloat(sin(angle)) * distance : 0)
            .scaleEffect(burst ? 1 : 0.01)
            .opacity(burst ? 0 : 1)
    }
}

private struct HelpStationBackdrop: View {
    var body: some View {
        Canvas { context, size in
            var grid = Path()
            for x in stride(from: 0.0, through: size.width, by: 34) {
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: 0.0, through: size.height, by: 34) {
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .color(.navPurple.opacity(0.05)), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

// MARK: - Post a request

private struct RequestHelpSheet: View {
    @EnvironmentObject private var lang: Lang
    @EnvironmentObject private var help: HelpStore
    @Environment(\.dismiss) private var dismiss
    let station: Station

    @State private var kind: HelpKind = .findExit
    @State private var spot: HelpSpot = .concourse
    @State private var targetExitId: String?
    @State private var note = ""
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(lang.t("需要哪種協助", "What do you need?"), selection: $kind) {
                        ForEach(HelpKind.allCases) { item in
                            Label(lang.t(item.titleZh, item.titleEn), systemImage: item.symbol)
                                .tag(item)
                        }
                    }
                } header: {
                    Text(lang.t("協助類型", "Type of help"))
                }

                if kind == .findExit {
                    Section {
                        Picker(lang.t("目標出口", "Target exit"), selection: $targetExitId) {
                            Text(lang.t("未指定", "Not specified")).tag(String?.none)
                            ForEach(station.exits) { exit in
                                Text("Exit \(exit.id) · \(lang.t(exit.nameZh, exit.nameEn))")
                                    .tag(Optional(exit.id))
                            }
                        }
                    } header: {
                        Text(lang.t("出口", "Exit"))
                    }
                }

                Section {
                    Picker(lang.t("你現在在哪裡？", "Where are you?"), selection: $spot) {
                        ForEach(HelpSpot.allCases) { item in
                            Text(lang.t(item.titleZh, item.titleEn)).tag(item)
                        }
                    }
                } header: {
                    Text(lang.t("位置", "Location"))
                }

                Section {
                    TextField(lang.t("例如：我在大堂，想去 A 出口", "e.g. I'm at the concourse, heading to Exit A"),
                              text: $note, axis: .vertical)
                        .lineLimit(2...4)
                    TextField(lang.t("你的稱呼（可選）", "Your name (optional)"), text: $name)
                } header: {
                    Text(lang.t("補充說明", "Details"))
                }
            }
            .navigationTitle(Text(lang.t("發布求助", "Post a request")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.t("取消", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(lang.t("發布", "Post")) { post() }
                }
            }
        }
    }

    private func post() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = HelpRequest(
            stationId: station.id,
            kind: kind,
            targetExitId: kind == .findExit ? targetExitId : nil,
            spot: spot,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            requesterName: trimmedName.isEmpty ? lang.t("我", "Me") : trimmedName
        )
        help.add(request)
        Haptics.success()
        dismiss()
    }
}

// MARK: - Detail: chat + precise location

private struct HelpMessage: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let isMe: Bool
}

private struct HelpDetailSheet: View {
    @EnvironmentObject private var lang: Lang
    @EnvironmentObject private var help: HelpStore
    @Environment(\.dismiss) private var dismiss
    let station: Station
    let request: HelpRequest
    let onNavigate: (StationExit) -> Void

    @State private var messages: [HelpMessage] = []
    @State private var draft = ""

    private var current: HelpRequest { help.request(id: request.id) ?? request }
    private var targetExit: StationExit? {
        guard let id = current.targetExitId else { return nil }
        return station.exits.first { $0.id == id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HelpLocationMap(spot: current.spot, exitId: current.targetExitId)
                        .frame(height: 200)

                    infoCard
                    chatSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .safeAreaInset(edge: .bottom) { chatInput }
            .navigationTitle(Text(lang.t("求助詳情", "Help request")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.t("關閉", "Close")) { dismiss() }
                }
            }
            .task {
                if messages.isEmpty {
                    messages = initialMessages()
                }
            }
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: current.kind.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(current.kind.tint, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(lang.t(current.kind.titleZh, current.kind.titleEn))
                        .font(.headline)
                    Text(lang.t("\(current.requesterName) · \(current.spot.titleZh)",
                                "\(current.requesterName) · \(current.spot.titleEn)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusBadge
            }

            if let exit = targetExit {
                Label(lang.t("前往出口 \(exit.id) · \(exit.nameZh)",
                             "To Exit \(exit.id) · \(exit.nameEn)"),
                      systemImage: "signpost.right.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.navPurple)
            }

            Divider()

            if let exit = targetExit {
                Button {
                    Haptics.impact(.medium)
                    dismiss()
                    onNavigate(exit)
                } label: {
                    Label(lang.t("帶佢去出口", "Guide them to the exit"),
                          systemImage: "figure.walk")
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            if current.status != .completed {
                Button {
                    help.complete(current.id)
                    Haptics.success()
                    dismiss()
                } label: {
                    Label(lang.t("已完成協助", "Mark as helped"),
                          systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .glassSurface(cornerRadius: 22)
    }

    private var statusBadge: some View {
        Text(current.status == .open
             ? lang.t("待協助", "Open")
             : (current.status == .claimed ? lang.t("協助中", "Helping") : lang.t("已完成", "Done")))
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(current.kind.tint, in: Capsule())
    }

    private var chatSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(lang.t("對話", "Conversation"))
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                ForEach(messages) { message in
                    HStack {
                        if message.isMe { Spacer(minLength: 40) }
                        Text(message.text)
                            .font(.subheadline)
                            .foregroundStyle(message.isMe ? .white : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                message.isMe
                                    ? AnyShapeStyle(Color.navPurple)
                                    : AnyShapeStyle(Color(.secondarySystemBackground)),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                        if !message.isMe { Spacer(minLength: 40) }
                    }
                }
            }
        }
    }

    private var chatInput: some View {
        HStack(spacing: 10) {
            TextField(lang.t("輸入訊息…", "Message…"), text: $draft)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .glassCapsule()
            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(isDraftEmpty ? Color(.tertiaryLabel) : Color.navPurple)
            }
            .disabled(isDraftEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var isDraftEmpty: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func initialMessages() -> [HelpMessage] {
        var list: [HelpMessage] = [
            HelpMessage(text: lang.t("你好，我喺\(current.spot.titleZh)，\(current.kind.titleZh)。",
                                    "Hi, I'm at the \(current.spot.titleEn) and need a hand."),
                        isMe: false)
        ]
        if !current.note.isEmpty {
            list.append(HelpMessage(text: current.note, isMe: false))
        } else {
            list.append(HelpMessage(text: lang.t("唔該幫幫我。", "Could you help me?"), isMe: false))
        }
        return list
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messages.append(HelpMessage(text: text, isMe: true))
        Haptics.tap()
        draft = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            messages.append(HelpMessage(text: lang.t("多謝你！麻煩晒。", "Thank you so much!"),
                                        isMe: false))
        }
    }
}

// MARK: - Schematic location card

private struct HelpLocationMap: View {
    @EnvironmentObject private var lang: Lang
    let spot: HelpSpot
    let exitId: String?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let spotPoint = CGPoint(x: size.width * spot.point.x,
                                    y: size.height * spot.point.y)

            ZStack(alignment: .topLeading) {
                Canvas { context, canvasSize in
                    var grid = Path()
                    for x in stride(from: 0.0, through: canvasSize.width, by: 32) {
                        grid.move(to: CGPoint(x: x, y: 0))
                        grid.addLine(to: CGPoint(x: x, y: canvasSize.height))
                    }
                    for y in stride(from: 0.0, through: canvasSize.height, by: 32) {
                        grid.move(to: CGPoint(x: 0, y: y))
                        grid.addLine(to: CGPoint(x: canvasSize.width, y: y))
                    }
                    context.stroke(grid, with: .color(.navPurple.opacity(0.06)), lineWidth: 1)

                    var route = Path()
                    route.move(to: spotPoint)
                    route.addQuadCurve(
                        to: CGPoint(x: canvasSize.width * 0.86, y: canvasSize.height * 0.20),
                        control: CGPoint(x: canvasSize.width * 0.42, y: canvasSize.height * 0.52)
                    )
                    context.stroke(route, with: .color(.navPurple.opacity(0.22)),
                                   style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    context.stroke(route, with: .color(.navPurple),
                                   style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }

                if let exitId {
                    Text(exitId)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.navPurple, in: Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .position(x: size.width * 0.86, y: size.height * 0.20)
                }

                PulsingMarker(tint: .red)
                    .position(spotPoint)

                Text(lang.t(spot.titleZh, spot.titleEn))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.navPurple, in: Capsule())
                    .position(x: spotPoint.x, y: max(spotPoint.y - 34, 16))
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(lang.t("求助者位置：\(spot.titleZh)", "Requester at: \(spot.titleEn)")))
    }
}

private struct PulsingMarker: View {
    let tint: Color
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.25))
                .frame(width: pulse ? 46 : 22, height: pulse ? 46 : 22)
                .opacity(pulse ? 0 : 1)
            Circle()
                .fill(tint)
                .frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                .shadow(color: tint.opacity(0.5), radius: 6)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}
