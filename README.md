# CoolMall iOS

原生 SwiftUI 商城客户端。App 负责依赖组装和导航，业务实现位于本地 Swift Package `Packages/MallKit`。

## 开发环境

- macOS 与 Xcode **27.0（27A266a）**，Swift **6.4**；完整版本约束见 `Scripts/check-toolchain.sh`。
- PATH 中可用的 **Python 3.9+**，供本地工程检查器使用；以 `python3 --version` 核对。
- 安装 iOS **27.0** Simulator runtime，并准备一台可启动的 iPhone 模拟器。
- 最低部署版本为 iOS **17.0**；最低系统和真机覆盖仍需单独验证。
- 首次解析依赖、真实 API 和图片加载需要网络。Nuke/NukeUI 固定为 **13.2.0**，保留仓库中的 `Package.resolved`。

## 检出与运行

```sh
git clone https://github.com/NAH4E5553/CoolMall-iOS.git
cd CoolMall-iOS
open CoolMalliOS.xcodeproj
```

在 Xcode 中选择共享 Scheme **CoolMalliOS** 和可用 iPhone 模拟器，再执行 Run。打开的是 `.xcodeproj`；本地 MallKit Package 已由工程引用，无需手工添加 Target、资源或依赖。

命令行仅构建 App：

```sh
xcodebuild build \
  -project CoolMalliOS.xcodeproj \
  -scheme CoolMalliOS \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/xcode \
  CODE_SIGNING_ALLOWED=NO
```

模拟器构建不需要发布签名或开发者的私有证书。App 默认使用正式接口；不要添加 UI 测试夹具启动参数。登录和账号业务需要有效账号及服务端可用，真实支付 SDK 未接入。

## 本地工程检查与测试

以下是按任务需要手动调用的入口，不会由 GitHub 自动执行：

```sh
python3 --version
Scripts/check-toolchain.sh
Scripts/check-format.sh
Scripts/check-source-boundaries.sh
```

需要自动修正格式时使用 `Scripts/format.sh`。模块矩阵、公开入口和状态合同的唯一规则源为 [ENGINEERING.md](ENGINEERING.md)。

完整本地验证入口会执行治理、格式与边界检查、Debug/Release 构建、实际测试发现及 Test Plan 执行：

```sh
xcrun simctl list devices available
MALL_SIMULATOR_ID='<替换为可用模拟器UDID>' Scripts/verify-local.sh
```

共享 Test Plan 同时包含 Package 测试和 UI 测试。结果写入 `.build/verification/`；未执行、零测试或环境不可用不能记作通过。既有断言、执行预算及有期限政策不因关闭远端 CI 而改变。

## 仓库内容与当前验证状态

GitHub 保留 App/Package 源码、正式资源、工程与依赖锁文件、业务测试，以及本地构建、格式、模块边界和验证所需工具。Evidence、旧备份、私人联调配置、停用实验、诊断候选和执行流水不是编译或运行的输入，也不随仓库交付。维护者已于2026-11-04批准删除Evidence及旧备份，不再假定原本地证据或过程档案仍可读取；Git中已提交的代码与规则历史仍保留。

GitHub Actions 当前关闭，仓库没有工作流入口；恢复 CI 或远端保护需由维护者另行安排。本地工程检查入口仍保留。

业务源码基线已完成维护者手动验收。本轮规则维护仅做定向离线治理正反例，未改 App、资源、工程、Package 或业务测试，未构建 App 或执行 App 行为测试；不能把治理自检记作新机器或所有运行环境验收通过。后续同事应按上面的固定工具链实际构建和验证，再报告各自环境的结果。
