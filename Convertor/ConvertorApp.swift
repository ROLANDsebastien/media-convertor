import Cocoa
import SwiftUI
import UserNotifications

@main
struct ConvertorApp: App {
    @StateObject private var languageManager = LanguageManager()
    @StateObject private var settings = Settings()
    private let notificationDelegate = NotificationDelegate()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("isDarkMode") private var isDarkMode = false

    var body: some Scene {
        WindowGroup("Convertor", id: "main") {
            ContentView(viewModel: ConvertorViewModel(settings: settings))
                .environment(\.locale, languageManager.currentLocale)
                .environmentObject(languageManager)
                .environmentObject(settings)
                .onAppear {
                    setupNotifications()
                    applyTheme()
                }
        }
        .defaultSize(width: 600, height: 400)
        .windowStyle(.automatic)
    }

    private func applyTheme() {
        NSApp.appearance = isDarkMode ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
    }

    private func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = notificationDelegate
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                print("Notification authorization granted.")
            } else if let error = error {
                print("Notification authorization error: \(error.localizedDescription)")
            }
        }
    }
}
