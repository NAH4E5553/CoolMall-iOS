import SwiftUI

/// Pure numeric decoration. The caller owns the meaning and freshness of the value.
public struct CountBadge: View {
    private let count: Int64
    public init(count: Int64) { self.count = count }
    public var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : String(count)).font(.caption2.bold())
                .foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 2)
                .frame(minWidth: 18, minHeight: 18).background(.red, in: Capsule()).fixedSize()
                .accessibilityLabel(String(count))
        }
    }
}
#Preview {
    HStack {
        CountBadge(count: 0); CountBadge(count: 8); CountBadge(count: 100)
    }
}
