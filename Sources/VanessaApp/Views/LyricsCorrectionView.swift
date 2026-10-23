import SwiftUI
import VanessaCore

/// 「校正歌词」窗口:调整本歌偏移;搜索网易云并手动指定正确的歌曲。
struct LyricsCorrectionView: View {
    let title: String
    let artist: String
    var onOffsetChange: (Double) -> Void
    var onSearch: (String) async throws -> [SongCandidate]
    var onSelect: (Int64) async throws -> Void

    @State private var offsetMs: Double
    @State private var query: String
    @State private var results: [SongCandidate] = []
    /// 搜索 / 加载过程的提示文案;nil 表示无提示。
    @State private var status: String?
    @State private var isBusy = false

    /// - Parameters:
    ///   - offsetMs: 本歌当前偏移(毫秒),作为滑块初值。
    ///   - onSearch: 按关键词搜索候选歌曲。
    ///   - onSelect: 指定歌曲 ID 并加载其歌词;失败时抛错。
    init(title: String, artist: String, offsetMs: Double,
         onOffsetChange: @escaping (Double) -> Void,
         onSearch: @escaping (String) async throws -> [SongCandidate],
         onSelect: @escaping (Int64) async throws -> Void) {
        self.title = title
        self.artist = artist
        self.onOffsetChange = onOffsetChange
        self.onSearch = onSearch
        self.onSelect = onSelect
        _offsetMs = State(initialValue: offsetMs)
        _query = State(initialValue: "\(title) \(artist)".trimmingCharacters(in: .whitespaces))
    }

    var body: some View {
        Form {
            Section("当前歌曲") {
                Text(artist.isEmpty ? title : "\(title) - \(artist)").lineLimit(1)
            }
            offsetSection
            searchSection
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 500)
        .onAppear { search() }   // 打开即用当前歌名搜索一次
    }

    /// 本歌偏移:叠加在全局「歌词偏移」上,只对这首歌生效。
    private var offsetSection: some View {
        Section("本歌偏移") {
            Slider(value: $offsetMs, in: -2000...2000, step: 10) {
                Text("偏移")
            } minimumValueLabel: { Text("-2s") } maximumValueLabel: { Text("+2s") }
            .onChange(of: offsetMs) { onOffsetChange($0) }
            HStack {
                Text("\(Int(offsetMs)) ms(叠加在全局偏移上,只对这首歌生效)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("重置") { offsetMs = 0 }
            }
        }
    }

    /// 手动选歌:搜索框 + 候选列表,点击候选即应用。
    private var searchSection: some View {
        Section("歌词不对？手动选歌") {
            HStack {
                TextField("歌名 / 歌手", text: $query).onSubmit { search() }
                Button("搜索") { search() }.disabled(isBusy)
            }
            if let status {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(results, id: \.id) { candidate in
                Button { select(candidate) } label: { candidateRow(candidate) }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
            }
        }
    }

    /// 候选行:歌名、歌手、时长。
    private func candidateRow(_ c: SongCandidate) -> some View {
        let seconds = c.durationMs / 1000
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(c.title).lineLimit(1)
                Text(c.artists.joined(separator: " / "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    /// 发起搜索;进行中或关键词为空时忽略。
    private func search() {
        let keywords = query.trimmingCharacters(in: .whitespaces)
        guard !keywords.isEmpty, !isBusy else { return }
        isBusy = true
        status = "搜索中…"
        Task {
            defer { isBusy = false }
            do {
                results = try await onSearch(keywords)
                status = results.isEmpty ? "没有找到结果,换个关键词试试" : nil
            } catch {
                NSLog("[Vanessa-Notch] 校正歌词搜索失败: %@", String(describing: error))
                status = "搜索失败,请检查网络后重试"
            }
        }
    }

    /// 应用选中的候选歌曲。
    private func select(_ candidate: SongCandidate) {
        guard !isBusy else { return }
        isBusy = true
        status = "正在加载歌词…"
        Task {
            defer { isBusy = false }
            do {
                try await onSelect(candidate.id)
                status = "已应用:\(candidate.title)"
            } catch {
                NSLog("[Vanessa-Notch] 加载歌曲 %lld 的歌词失败: %@", candidate.id, String(describing: error))
                status = "加载歌词失败,请稍后重试"
            }
        }
    }
}
