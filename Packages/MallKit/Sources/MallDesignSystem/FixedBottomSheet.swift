import SwiftUI

/// Fixed visual container. Only the header owns dismissal drags; content keeps its own scrolling.
public struct FixedBottomSheet<Content: View>: View {
    private let title: String
    private let onDismiss: () -> Void
    private let content: Content
    @GestureState private var drag: CGFloat = 0
    public init(
        title: String, onDismiss: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title; self.onDismiss = onDismiss; self.content = content()
    }
    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.32).ignoresSafeArea().onTapGesture(perform: onDismiss)
                    .accessibilityLabel("收起弹框").accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("fixedSheet.backdrop")
                VStack(spacing: 0) {
                    VStack(spacing: 16) {
                        Capsule().fill(.secondary.opacity(0.25)).frame(width: 40, height: 4)
                        Text(title).font(.headline).padding(.bottom, 18)
                    }.padding(.top, 16).frame(maxWidth: .infinity).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 10, coordinateSpace: .global)
                                .updating($drag) { value, state, _ in
                                    if value.translation.height > abs(value.translation.width) {
                                        state = max(0, value.translation.height)
                                    }
                                }.onEnded { value in
                                    if value.translation.height >= 64,
                                        value.translation.height > abs(value.translation.width)
                                            * 1.3
                                    {
                                        onDismiss()
                                    }
                                }
                        )
                        .accessibilityIdentifier("fixedSheet.header")
                    content.frame(maxWidth: .infinity, maxHeight: .infinity)
                }.frame(height: geometry.size.height * 0.70)
                    .padding(.bottom, geometry.safeAreaInsets.bottom)
                    .background(
                        .background,
                        in: UnevenRoundedRectangle(
                            topLeadingRadius: 24, topTrailingRadius: 24)
                    )
                    .offset(y: drag).animation(.interactiveSpring(), value: drag)
            }.ignoresSafeArea(edges: .bottom)
        }.accessibilityAction(.escape, onDismiss)
    }
}
