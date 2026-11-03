import Foundation

/// Raw `POST goods/type/list` node. The captured production response is a FLAT
/// array (43 nodes, 10 roots, one display level) whose fields are id/name/
/// parentId/sortNum/pic/status/createTime/updateTime. Required id/name are
/// non-optional: a missing or wrong-typed required field is a payload failure,
/// never a silent default. `sortNum` keeps the reference client's
/// `coerceInputValues` compatibility for absent/null (mapped to 0); status and
/// timestamps are not consumed by the category page.
struct CategoryDTO: Decodable {
    let id: Int64
    let name: String
    let parentId: Int64?
    let sortNum: Int?
    let pic: String?
}
