import Foundation
import MallCore
import UserNotifications

/// Only invoked after the user requests a code; never asks permission at launch.
/// The notification is transient, has no sound/code logging and is replaced on resend.
@MainActor public final class LocalVerificationCodeNotifier: VerificationCodeDelivering, Sendable {
    private let center = UNUserNotificationCenter.current()
    private let delegate = LoginNotificationDelegate()
    public init() { center.delegate = delegate }
    public func prepare() async throws {
        var settings = await center.notificationSettings()
        try Task.checkCancellation()
        if settings.authorizationStatus == .notDetermined {
            _ = try await center.requestAuthorization(options: [.alert])
            settings = await center.notificationSettings()
        }
        try Task.checkCancellation()
        guard settings.authorizationStatus == .authorized, settings.alertSetting == .enabled else {
            throw AccountFailure.notificationsDenied
        }
    }
    public func deliver(_ code: String) async throws {
        guard LoginValidation.code(code) else { throw AccountFailure.invalidPayload }
        try await prepare()
        try Task.checkCancellation()
        let content = UNMutableNotificationContent()
        content.title = "青商城登录验证码"
        content.body = "验证码：" + code + "。请勿向他人透露。"
        let request = UNNotificationRequest(
            identifier: "CoolMall.login-code", content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        do { try await center.add(request) } catch { throw AccountFailure.notificationDelivery }
        if Task.isCancelled {
            center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
            center.removeDeliveredNotifications(withIdentifiers: [request.identifier])
            throw CancellationError()
        }
    }
}

private final class LoginNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable
{
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    )
        async -> UNNotificationPresentationOptions
    {
        notification.request.identifier == "CoolMall.login-code" ? [.banner, .list] : []
    }
}
