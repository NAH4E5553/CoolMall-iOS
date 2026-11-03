import Foundation
import MallCore
import Testing
@testable import MallData

struct AddressServiceTests {
    private var base: URL { URL(string: "https://coupon.invalid/app/")! }
    private var input: ShippingAddressInput {
        ShippingAddressInput(
            contact: " 测试 ", phone: "13800000000", province: "北京市", city: "北京市", district: "东城区",
            address: "测试街道", isDefault: false)
    }
    private var row: String {
        #"{"id":7,"contact":"测试","phone":"13800000000","province":"北京市","city":"北京市","district":"东城区","address":"测试街道","isDefault":false}"#
    }
    private func session() -> SessionCoordinator {
        SessionCoordinator(
            loader: CouponAuthLoader(), storage: CouponAuthStorage(existing: true),
            environmentURL: base)
    }
    private func service(_ transport: CouponTransport, session: SessionCoordinator? = nil)
        -> HTTPAddressService
    {
        HTTPAddressService(
            environment: .init(baseURL: base), session: session ?? self.session(),
            transport: transport)
    }
    @Test func exactAddUpdateAndDeleteCodeOnlyAcknowledgmentsAndFalseEncoding() async throws {
        for body in [
            #"{"code":1000}"#, #"{"code":1000,"data":null}"#, #"{"code":1000,"data":{"id":7}}"#,
        ] {
            let transport = CouponTransport(data: Data(body.utf8)); let service = service(transport)
            try await service.saveAddress(accountID: 1, id: nil, input: input)
            try await service.saveAddress(accountID: 1, id: 7, input: input)
            try await service.deleteAddress(accountID: 1, id: 7)
            let requests = await transport.requests
            #expect(
                requests.map { $0.url?.path } == [
                    "/app/user/address/add", "/app/user/address/update", "/app/user/address/delete",
                ])
            for (index, request) in requests.enumerated() {
                #expect(request.httpMethod == "POST");
                #expect(request.value(forHTTPHeaderField: "Authorization") == "synthetic-session")
                let bytes = try #require(request.httpBody)
                let json = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
                if index < 2 {
                    #expect(json["isDefault"] as? Bool == false);
                    #expect(json["contact"] as? String == "测试")
                    #expect(json["userId"] == nil); #expect(json["createTime"] == nil)
                    #expect(json["id"] as? Int == (index == 1 ? 7 : nil));
                    #expect(json.count == (index == 1 ? 8 : 7))
                } else {
                    #expect(json["ids"] as? [Int] == [7]); #expect(json.count == 1)
                }
            }
        }
    }
    @Test func pageAndInfoHaveExactRequestAndRejectWrongIdentityOrMalformedPage() async throws {
        let page =
            #"{"code":1000,"data":{"list":["# + row
            + #"],"pagination":{"page":1,"size":10,"total":1}}}"#
        let transport = CouponTransport(data: Data(page.utf8));
        let values = try await service(transport).loadAddresses(accountID: 1, page: 1, pageSize: 10)
        #expect(values.items.first?.id == 7)
        let pageRequest = try #require(await transport.requests.first)
        let pageBody = try #require(pageRequest.httpBody)
        let query = try #require(JSONSerialization.jsonObject(with: pageBody) as? [String: Any])
        #expect(query["page"] as? Int == 1); #expect(query["size"] as? Int == 10);
        #expect(query["sort"] as? String == "desc")
        let info = CouponTransport(data: Data((#"{"code":1000,"data":"# + row + "}").utf8))
        #expect(try await service(info).loadAddress(accountID: 1, id: 7).value.contact == "测试")
        let request = try #require(await info.requests.first); #expect(request.httpMethod == "GET")
        #expect(request.url?.query == "id=7"); #expect(request.httpBody == nil)
        await #expect(throws: PageReadFailure.invalidResponse) {
            try await service(info).loadAddress(accountID: 1, id: 8)
        }
        let malformed = CouponTransport(
            data: Data(page.replacingOccurrences(of: #""total":1"#, with: #""total":2"#).utf8))
        await #expect(throws: PageReadFailure.invalidResponse) {
            try await service(malformed).loadAddresses(accountID: 1, page: 1, pageSize: 10)
        }
    }
    @Test func guestWrongIdentityInvalidInputAndConcurrentWritesNeverDispatch() async throws {
        let transport = CouponTransport(data: Data(#"{"code":1000}"#.utf8), hold: true);
        let service = service(transport)
        await #expect(throws: AddressWriteFailure.authenticationRequired) {
            try await service.saveAddress(accountID: 2, id: nil, input: input)
        }
        await #expect(throws: AddressWriteFailure.authenticationRequired) {
            try await service.deleteAddress(accountID: 0, id: 1)
        }
        await #expect(throws: AddressWriteFailure.invalidInput) {
            try await service.saveAddress(accountID: 1, id: nil, input: .init())
        }
        let wrongEnvironment = HTTPAddressService(
            environment: .init(baseURL: base.appending(path: "other/")), session: session(),
            transport: transport)
        await #expect(throws: AddressWriteFailure.invalidConfiguration) {
            try await wrongEnvironment.saveAddress(accountID: 1, id: nil, input: input)
        }
        #expect(await transport.requests.isEmpty)
        let first = Task { try await service.saveAddress(accountID: 1, id: nil, input: input) }
        await transport.started()
        await #expect(throws: AddressWriteFailure.busy) {
            try await service.deleteAddress(accountID: 1, id: 7)
        }
        #expect(await transport.requests.count == 1); await transport.release();
        try await first.value
    }
    @Test func businessMessageUnknownResponseAndHTTPFailuresNeverReplay() async {
        for (body, status, expected) in [
            (
                #"{"code":500,"message":"地址不存在"}"#, 200,
                AddressWriteFailure.rejected(code: 500, message: "地址不存在")
            ), (#"{"code":500,"message":{}}"#, 200, .rejected(code: 500, message: nil)),
            ("invalid", 200, .unconfirmed), (#"{"code":1000}"#, 500, .unconfirmed),
            (#"{"code":1000}"#, 401, .authenticationRequired),
        ] {
            let transport = CouponTransport(data: Data(body.utf8), status: status)
            await #expect(throws: expected) {
                try await service(transport).saveAddress(accountID: 1, id: nil, input: input)
            }
            #expect(await transport.requests.count == 1)
        }
    }
    @Test func logoutAndReloginInvalidateLateReadAndWriteSuccessAndFailure() async throws {
        for write in [false, true] {
            for fail in [false, true] {
                let transport = CouponTransport(
                    data: Data((#"{"code":1000,"data":"# + row + "}").utf8), hold: true, fail: fail)
                let session = session(); let service = service(transport, session: session)
                let task = Task {
                    if write {
                        try await service.saveAddress(accountID: 1, id: nil, input: input)
                    } else {
                        _ = try await service.loadAddress(accountID: 1, id: 7)
                    }
                }
                await transport.started(); try await session.logout();
                try await session.login(.password(phone: "13800000000", password: "test-only"))
                await transport.release();
                await #expect(throws: CancellationError.self) { try await task.value }
                #expect(await transport.requests.count == 1)
            }
        }
    }
    @Test func pinnedRegionResourceHasAllLevelsUniqueIDsAndSpecialRegions() async throws {
        let values = try await BundledAddressRegions().loadRegions()
        #expect(values.count == 34); #expect(values.flatMap(\.children).count == 369)
        let leaves = values.flatMap(\.children).flatMap(\.children); #expect(leaves.count == 3478)
        let all = values + values.flatMap(\.children) + leaves
        #expect(Set(all.map(\.id)).count == all.count)
        let beijing = try #require(values.first { $0.name == "北京市" });
        #expect(beijing.children.first?.name == "北京市")
        #expect(beijing.children.first?.children.contains { $0.name == "东城区" } == true)
        #expect(values.contains { $0.name == "台湾省" });
        #expect(values.contains { $0.name == "香港特别行政区" });
        #expect(values.contains { $0.name == "澳门特别行政区" })
        #expect(
            values.first { $0.name == "湖北省" }?.children.first { $0.name == "省直辖县" }?.children
                .contains { $0.name == "仙桃市" } == true)
        #expect(
            values.first { $0.name == "广东省" }?.children.first { $0.name == "东莞市" }?.children.isEmpty
                == false)
    }
}
