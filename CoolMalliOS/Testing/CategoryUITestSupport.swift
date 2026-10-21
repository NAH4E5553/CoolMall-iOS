#if DEBUG
    import Foundation
    import MallCore
    import SwiftUI

    /// DEBUG-only category fixture assembly. `--ui-category-fixture` selects a
    /// deterministic service; a present flag with a missing/unknown value fails
    /// closed to an explicit configuration-error view instead of falling through
    /// to the production HTTP service. No production path is replaced in
    /// Release, and fixtures never decode MallData internals from the App.
    struct CategoryUITestSupport {
        enum FixtureMode: String {
            case valid
            case empty
            case error
            case retry
            case pending
        }

        let mode: FixtureMode?
        let configError: Bool
        let service: (any CategoryLoading)?

        @MainActor init(arguments: [String] = ProcessInfo.processInfo.arguments) {
            guard let flag = arguments.firstIndex(of: "--ui-category-fixture") else {
                mode = nil
                configError = false
                service = nil
                return
            }
            let next = flag + 1
            guard next < arguments.count, !arguments[next].hasPrefix("-"),
                let mode = FixtureMode(rawValue: arguments[next])
            else {
                self.mode = nil
                configError = true
                service = nil
                return
            }
            self.mode = mode
            configError = false
            switch mode {
            case .valid: service = FixtureCategoryService(mode: .valid)
            case .empty: service = FixtureCategoryService(mode: .empty)
            case .error: service = FixtureCategoryService(mode: .error)
            case .retry: service = RetryCategoryService()
            case .pending: service = PendingCategoryService()
            }
        }
    }

    /// Deterministic service over a legible subset of the captured production
    /// tree (10-root/43-node response, cf5029b evidence): six real roots with
    /// their direct children, one root WITHOUT children, plus a deeper node and
    /// an unknown-parent node that must never be displayed. Images are nil so
    /// fixture layout/scroll evidence does not depend on the network.
    final class FixtureCategoryService: CategoryLoading, Sendable {
        enum Mode { case valid, empty, error }

        private let mode: Mode

        init(mode: Mode) {
            self.mode = mode
        }

        func loadCategories() async throws -> [CategoryNode] {
            switch mode {
            case .valid: return Self.valid
            case .empty: return []
            case .error: throw CategoryLoadFailure.networkUnavailable
            }
        }

        static let valid: [CategoryNode] = [
            CategoryNode(id: 800001, name: "手机", parentID: nil, sortNum: 1, imageURL: nil),
            CategoryNode(
                id: 801001, name: "Xiaomi 数字旗舰", parentID: 800001, sortNum: 1, imageURL: nil),
            CategoryNode(
                id: 801002, name: "Xiaomi MIX系列", parentID: 800001, sortNum: 2, imageURL: nil),
            CategoryNode(
                id: 801003, name: "Xiaomi Civi", parentID: 800001, sortNum: 3, imageURL: nil),
            CategoryNode(id: 801004, name: "K系列", parentID: 800001, sortNum: 4, imageURL: nil),
            CategoryNode(id: 801005, name: "Note系列", parentID: 800001, sortNum: 5, imageURL: nil),
            CategoryNode(id: 801006, name: "Turbo系列", parentID: 800001, sortNum: 6, imageURL: nil),
            CategoryNode(id: 801007, name: "数字系列", parentID: 800001, sortNum: 7, imageURL: nil),
            CategoryNode(id: 800002, name: "平板", parentID: nil, sortNum: 2, imageURL: nil),
            CategoryNode(id: 801008, name: "REDMI平板", parentID: 800002, sortNum: 1, imageURL: nil),
            CategoryNode(id: 801009, name: "Xiaomi平板", parentID: 800002, sortNum: 2, imageURL: nil),
            CategoryNode(id: 800003, name: "穿戴", parentID: nil, sortNum: 3, imageURL: nil),
            CategoryNode(id: 801010, name: "智能手环", parentID: 800003, sortNum: 1, imageURL: nil),
            CategoryNode(id: 801011, name: "智能手表", parentID: 800003, sortNum: 2, imageURL: nil),
            CategoryNode(id: 801012, name: "智能耳机", parentID: 800003, sortNum: 3, imageURL: nil),
            CategoryNode(id: 801013, name: "其他穿戴", parentID: 800003, sortNum: 4, imageURL: nil),
            CategoryNode(id: 800004, name: "电脑办公", parentID: nil, sortNum: 4, imageURL: nil),
            CategoryNode(id: 801014, name: "笔记本", parentID: 800004, sortNum: 1, imageURL: nil),
            CategoryNode(id: 801015, name: "显示器", parentID: 800004, sortNum: 2, imageURL: nil),
            CategoryNode(id: 801016, name: "办公配件", parentID: 800004, sortNum: 3, imageURL: nil),
            CategoryNode(id: 800005, name: "电视影音", parentID: nil, sortNum: 5, imageURL: nil),
            CategoryNode(id: 801017, name: "旗舰系列", parentID: 800005, sortNum: 1, imageURL: nil),
            CategoryNode(id: 801018, name: "性价比爆款", parentID: 800005, sortNum: 2, imageURL: nil),
            CategoryNode(id: 801019, name: "巨幕影院", parentID: 800005, sortNum: 3, imageURL: nil),
            CategoryNode(id: 800006, name: "生活家电", parentID: nil, sortNum: 6, imageURL: nil),
            CategoryNode(id: 801020, name: "热销推荐", parentID: 800006, sortNum: 1, imageURL: nil),
            CategoryNode(id: 801021, name: "主推新品", parentID: 800006, sortNum: 2, imageURL: nil),
            CategoryNode(id: 801022, name: "波轮洗衣机", parentID: 800006, sortNum: 3, imageURL: nil),
            CategoryNode(id: 800099, name: "无子分类", parentID: nil, sortNum: 7, imageURL: nil),
            // Deeper/unknown-parent nodes: valid payload, never rendered.
            CategoryNode(
                id: 801099, name: "更深层级（不应展示）", parentID: 801001, sortNum: 1, imageURL: nil),
            CategoryNode(
                id: 801098, name: "未知父节点（不应展示）", parentID: 999_999, sortNum: 1, imageURL: nil),
        ]
    }

    actor RetryCategoryService: CategoryLoading {
        private var calls = 0

        func loadCategories() async throws -> [CategoryNode] {
            calls += 1
            if calls == 1 { throw CategoryLoadFailure.networkUnavailable }
            return FixtureCategoryService.valid
        }
    }

    actor PendingCategoryService: CategoryLoading {
        func loadCategories() async throws -> [CategoryNode] {
            while true {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    /// Explicit DEBUG configuration error; never used by a valid fixture launch.
    struct ConfigErrorCategoryService: CategoryLoading {
        func loadCategories() async throws -> [CategoryNode] {
            throw CategoryLoadFailure.invalidConfiguration
        }
    }

    struct CategoryTestConfigErrorView: View {
        var body: some View {
            VStack(spacing: 12) {
                Text("分类测试配置错误").font(.headline)
                Text("启动参数缺失或非法，已停止读取")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("category.testConfigError")
        }
    }
#endif
