import MallCore
import Testing

@Test func specificationAndScopeIdentity() {
    let first = CartItemID(productID: 1, specificationID: 1)
    let second = CartItemID(productID: 1, specificationID: 2)
    #expect(Set([first, second]).count == 2)
    #expect(
        CartScope(environment: "fixture", accountID: nil)
            != CartScope(environment: "fixture", accountID: "user"))
}
