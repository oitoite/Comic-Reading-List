import SwiftUI
import ReadingListCore

@main
struct UnlimitedReadingListApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(model.colorScheme)
                .onOpenURL { url in
                    // Share links: unlimitedreadinglist://list/<code>, or the web app's
                    // https://…/#list=<code> when universal links are configured.
                    model.handleIncoming(url: url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { model.handleIncoming(url: url) }
                }
        }
    }
}
