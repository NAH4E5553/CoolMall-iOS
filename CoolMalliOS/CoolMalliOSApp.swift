import SwiftUI

@main
struct CoolMalliOSApp: App {
    private let dependencies = AppDependencies()
    var body: some Scene {
        WindowGroup { RootView(dependencies: dependencies) }
    }
}
