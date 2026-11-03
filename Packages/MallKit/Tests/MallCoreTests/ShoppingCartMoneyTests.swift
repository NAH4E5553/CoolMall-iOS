import Foundation
import MallCore
import Testing

@Suite struct ShoppingCartMoneyTests {
    @Test func exactCurrencyAndAggregate() throws {
        let price = try CartMoney(yuan: Decimal(string: "3999.01") ?? 0)
        #expect(price.cents == 399901)
        #expect(try price.multiplied(by: 3).cents == 1199703)
        #expect(try price.adding(CartMoney(yuan: 1)).cents == 400001)
    }
    @Test func rejectsRoundingNegativeAndOverflow() throws {
        #expect(throws: ShoppingCartFailure.invalidMoney) {
            try CartMoney(yuan: Decimal(string: "0.001") ?? 0)
        }
        #expect(throws: ShoppingCartFailure.invalidMoney) { try CartMoney(yuan: -1) }
        let largest = try CartMoney(yuan: Decimal(Int64.max) / 100)
        #expect(throws: ShoppingCartFailure.invalidMoney) { try largest.multiplied(by: 2) }
        #expect(throws: ShoppingCartFailure.invalidMoney) { try largest.adding(CartMoney(yuan: 1)) }
    }
    @Test func decodedMoneyCannotBypassNonnegativeInvariant() throws {
        #expect(throws: ShoppingCartFailure.invalidMoney) {
            try JSONDecoder().decode(CartMoney.self, from: Data(#"{"cents":-1}"#.utf8))
        }
    }
    @Test func selectedRowsPiecesAndGroupsAreDistinct() throws {
        let scope = CartScope(environment: "test", accountID: nil)
        let a = CartQuote(
            productID: 1, specificationID: 10, title: "手机", specification: "白", imageURL: nil,
            price: try CartMoney(yuan: 100), stock: 10)
        let b = CartQuote(
            productID: 1, specificationID: 11, title: "手机", specification: "黑", imageURL: nil,
            price: try CartMoney(yuan: 120), stock: 10)
        let value = ShoppingCartSnapshot(
            scope: scope, revision: 7,
            lines: [.init(quote: a, quantity: 3), .init(quote: b, quantity: 2)])
        #expect(try value.itemCount() == 5)
        #expect(value.quantities.count == 2)
        #expect(try value.total(for: [a.id]).cents == 30000)
        #expect(try value.total(for: [a.id, b.id]).cents == 54000)
        #expect(try value.total(for: []).cents == 0)
    }
}
