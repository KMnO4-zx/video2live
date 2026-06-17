import AppKit
import SwiftUI

@main
struct Video2LiveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 1120, minHeight: 760)
                .background(WindowAccessor { window in
                    window.title = "Video2Live"
                    window.titleVisibility = .hidden
                    window.titlebarAppearsTransparent = true
                    window.isMovableByWindowBackground = false
                    window.backgroundColor = .clear
                })
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSmokeCommand.runIfRequested()
    }
}

struct WindowAccessor: NSViewRepresentable {
    var onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) { }
}
