import SwiftUI

@main
struct VeilVPNApp: App {
    @StateObject private var controller = VeilController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(controller)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var controller: VeilController

    var body: some View {
        ZStack {
            Color(red: 0x0E / 255, green: 0x13 / 255, blue: 0x30 / 255).ignoresSafeArea()
            VeilWebView(webView: controller.webView).ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $controller.showBrowser) {
            BrowserView(connected: AppState.connectedId != nil) {
                controller.showBrowser = false
            }
        }
    }
}
