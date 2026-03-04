import SwiftUI

/// CmdMD 스타일 토스트 알림
struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }
}

/// Toast를 화면 상단에 오버레이하는 modifier
struct ToastOverlay: ViewModifier {
    let message: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let message {
                ToastView(message: message)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.15), value: message)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: message)
    }
}

extension View {
    func toast(message: String?) -> some View {
        modifier(ToastOverlay(message: message))
    }
}
