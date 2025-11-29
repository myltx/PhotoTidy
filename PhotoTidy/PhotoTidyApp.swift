
import SwiftUI

// MARK: - App 入口

@main
struct PhotoTidyApp: App {
    var body: some Scene {
        WindowGroup {
            if FeatureToggles.useZeroLatencyArchitectureDemo {
                ZeroLatencyRootView()
            } else {
                ContentView()
            }
        }
    }
}
