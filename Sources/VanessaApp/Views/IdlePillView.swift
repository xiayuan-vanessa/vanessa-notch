import SwiftUI

/// 装饰性音频均衡条(米白色,非真实频谱)。
/// 播放/暂停切换为两棵不同子视图:暂停时带重复动画的视图被整体销毁,确保动画真正停止。
struct DecorativeBars: View {
    let isPlaying: Bool
    var body: some View {
        Group {
            if isPlaying {
                AnimatedEqualizer()
            } else {
                StaticBars()
            }
        }
        .frame(height: 15, alignment: .center)
    }
}

/// 播放态:各条错峰无限往返跳动。
private struct AnimatedEqualizer: View {
    @State private var up = false
    private let lows: [CGFloat]  = [3, 5, 3, 4]
    private let highs: [CGFloat] = [10, 14, 8, 12]
    private let durations: [Double] = [0.50, 0.36, 0.62, 0.44]
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(Color.notchAccent)
                    .frame(width: 2.5, height: up ? highs[i] : lows[i])
                    .animation(.easeInOut(duration: durations[i]).repeatForever(autoreverses: true), value: up)
            }
        }
        .onAppear { up = true }
    }
}

/// 暂停态:静止的短条(高度各异,像被定格的均衡器,而非一排小点)。
private struct StaticBars: View {
    private let rests: [CGFloat] = [6, 10, 6, 8]
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(Color.notchAccent)
                    .frame(width: 2.5, height: rests[i])
            }
        }
    }
}

/// 空闲胶囊:点击打开设置。
struct IdlePillView: View {
    let isWarning: Bool
    var onTap: () -> Void
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isWarning ? "exclamationmark.triangle.fill" : "music.note")
                .font(.system(size: 11))
                .foregroundStyle(isWarning ? .yellow : .white.opacity(0.8))
        }
        .padding(.horizontal, 12).frame(height: 22)
        .background(Capsule().fill(.black.opacity(0.82)))
        .contentShape(Capsule())
        .onTapGesture { onTap() }
    }
}
