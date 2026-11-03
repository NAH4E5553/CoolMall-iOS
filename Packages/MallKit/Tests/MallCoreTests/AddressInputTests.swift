import Foundation
import MallCore
import Testing

struct AddressInputTests {
    @Test func requiredFieldsPhoneAndNormalizationKeepFalseDefault() {
        let input = ShippingAddressInput(
            contact: " 测试 ", phone: " 13800000000 ", province: " 河北省 ", city: " 石家庄市 ",
            district: " 桥西区 ", address: " 街道 1号 ", isDefault: false)
        #expect(input.isValid); #expect(input.normalized.contact == "测试")
        #expect(input.normalized.phone == "13800000000");
        #expect(input.normalized.isDefault == false)
        for phone in ["12800000000", "1380000000", "138000000000", "1380000000a", "１3800000000"] {
            var value = input; value.phone = phone; #expect(!value.isValid)
        }
        for field in [\ShippingAddressInput.contact, \.province, \.city, \.district, \.address] {
            var value = input; value[keyPath: field] = " "; #expect(!value.isValid)
        }
    }
}
