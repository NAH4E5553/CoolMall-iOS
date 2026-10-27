import Foundation
import MallDesignSystem
import SwiftUI

/// Android detail roles, scoped to this page. Sizes scale with the user's text setting.
enum ProductDetailStyle {
    static let accent = Color(red: 70 / 255, green: 92 / 255, blue: 1)
    static let danger = Color(red: 1, green: 43 / 255, blue: 43 / 255)
    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(white: 0.067) : Color(red: 241 / 255, green: 244 / 255, blue: 250 / 255)
    }
    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.106) : .white
    }
    static func border(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.14) : Color(white: 0.933)
    }
    static func onSurface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 209 / 255) : Color(white: 24 / 255)
    }
    static func secondary(_ scheme: ColorScheme) -> Color {
        onSurface(scheme).opacity(0.75)
    }
    static func tertiary(_ scheme: ColorScheme) -> Color {
        let variant =
            scheme == .dark
            ? Color(red: 202 / 255, green: 196 / 255, blue: 208 / 255)
            : Color(red: 73 / 255, green: 69 / 255, blue: 79 / 255)
        return variant.opacity(0.6)
    }
    static let ratingActive = Color(red: 1, green: 103 / 255, blue: 0)
    static let ratingInactive = Color(white: 192 / 255)
    // Fixed Android primary lerped 15% toward white/black in Oklab.
    static let gradientStart = Color(red: 92 / 255, green: 121 / 255, blue: 1)
    static let gradientEnd = Color(red: 55 / 255, green: 72 / 255, blue: 206 / 255)
    static func number(_ value: Decimal) -> String {
        value.formatted(
            .number.locale(Locale(identifier: "zh_CN"))
                .grouping(.never).precision(.fractionLength(0...2)))
    }
}

struct ProductDetailPriceView: View {
    let amount: Decimal
    var compact = false
    @ScaledMetric private var couponIntegerSize = 18.0
    @ScaledMetric private var integerSize = 22.0
    @ScaledMetric private var fractionSize = 12.0
    private var parts: [String] {
        amount.formatted(
            .number.locale(Locale(identifier: "en_US_POSIX"))
                .grouping(.never).precision(.fractionLength(2))
        ).components(separatedBy: ".")
    }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("¥").font(.system(size: fractionSize)).padding(.trailing, 1)
            Text(parts[0]).font(
                .system(size: compact ? couponIntegerSize : integerSize, weight: .bold))
            Text("." + (parts.last ?? "00")).font(.system(size: fractionSize))
        }
        .foregroundStyle(ProductDetailStyle.danger)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            amount.formatted(
                .currency(code: "CNY").locale(Locale(identifier: "zh_CN")).grouping(.never)))
    }
}

struct ProductDetailSectionTitle: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    @ScaledMetric private var titleSize = 14.0
    var body: some View {
        HStack(spacing: 8) {
            Capsule().fill(ProductDetailStyle.accent).frame(width: 4, height: 20)
            Text(title).font(.system(size: titleSize, weight: .bold))
                .foregroundStyle(ProductDetailStyle.onSurface(scheme))
            Spacer(minLength: 0)
        }
    }
}

/// Add is injected; purchase remains an entrance without order side effects.
struct ProductDetailPurchaseButtons: View {
    var roundedCapsule = true
    var onAdd: () -> Void = {}
    var onBuy: () -> Void = {}
    var isAdding = false
    var addIdentifier = "detail.addCart"
    var canAdd = true
    @ScaledMetric private var labelSize = 14.0
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onAdd) {
                Text(isAdding ? "处理中" : "加入购物车").lineLimit(2).fixedSize(
                    horizontal: false, vertical: true
                ).frame(
                    maxWidth: .infinity
                ).padding(.vertical, roundedCapsule ? 12 : 8).frame(
                    minHeight: roundedCapsule ? 48 : 34)
            }
            .disabled(isAdding || !canAdd).accessibilityIdentifier(addIdentifier)
            .foregroundStyle(ProductDetailStyle.accent)
            .background(
                RoundedRectangle(cornerRadius: roundedCapsule ? 100 : 8).stroke(
                    ProductDetailStyle.accent, lineWidth: 1))
            Button(action: onBuy) {
                Text("立即购买").bold().lineLimit(2).fixedSize(horizontal: false, vertical: true).frame(
                    maxWidth: .infinity
                ).padding(.vertical, roundedCapsule ? 12 : 8).frame(
                    minHeight: roundedCapsule ? 48 : 34)
            }
            .disabled(isAdding || !canAdd).accessibilityIdentifier(
                addIdentifier == "detail.spec.addCart" ? "detail.spec.buyNow" : "detail.buyNow"
            )
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [ProductDetailStyle.gradientStart, ProductDetailStyle.gradientEnd],
                    startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: roundedCapsule ? 100 : 8))
        }
        .font(.system(size: labelSize))
        .buttonStyle(.plain)
    }
}

struct ProductDetailBottomBar: View {
    var onAdd: () -> Void = {}
    var onBuy: () -> Void = {}
    var onOpenCart: () -> Void = {}
    var cartItemCount: Int64?
    var isAdding = false
    var canAdd = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    HStack(spacing: 24) {
                        entrance("客服", icon: "detail-service")
                        entrance("购物车", icon: "detail-cart", action: onOpenCart)
                        Spacer(minLength: 0)
                    }
                    ProductDetailPurchaseButtons(
                        roundedCapsule: false, onAdd: onAdd, onBuy: onBuy, isAdding: isAdding,
                        canAdd: canAdd)
                }
            } else {
                HStack(spacing: 16) {
                    entrance("客服", icon: "detail-service")
                    entrance("购物车", icon: "detail-cart", action: onOpenCart)
                    ProductDetailPurchaseButtons(
                        roundedCapsule: false, onAdd: onAdd, onBuy: onBuy, isAdding: isAdding,
                        canAdd: canAdd)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(ProductDetailStyle.surface(scheme))
    }
    private func entrance(_ text: String, icon: String, action: @escaping () -> Void = {})
        -> some View
    {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(icon, bundle: .module).resizable().frame(width: 20, height: 20)
                    .overlay(alignment: .topTrailing) {
                        if text == "购物车", let cartItemCount, cartItemCount > 0 {
                            CountBadge(count: cartItemCount).offset(x: 14, y: -8)
                                .accessibilityHidden(true)
                        }
                    }
                Text(text).font(.caption2)
            }
            .frame(minWidth: 32, minHeight: 44)
        }
        .buttonStyle(.plain).foregroundStyle(ProductDetailStyle.onSurface(scheme))
        .accessibilityIdentifier(text == "购物车" ? "detail.openCart" : "detail.service")
        .accessibilityValue(text == "购物车" ? cartItemCount.map { "\($0)件商品" } ?? "数量暂不可用" : "")
        .accessibilityHint(text == "购物车" ? "打开独立购物车" : "功能暂未实现")
    }
}
