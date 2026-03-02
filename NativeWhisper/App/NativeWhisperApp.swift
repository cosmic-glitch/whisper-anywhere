import AppKit
import SwiftUI

final class NativeWhisperAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct NativeWhisperApp: App {
    @NSApplicationDelegateAdaptor(NativeWhisperAppDelegate.self) private var appDelegate
    @StateObject private var controller = MenuBarController()

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 10) {
                Text("Status: \(controller.statusText)")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: {
                    controller.openConfiguration()
                }) {
                    Text("Configure")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button(action: {
                    controller.quitApp()
                }) {
                    Text("Quit")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .frame(minWidth: 220, alignment: .leading)
            .onAppear {
                controller.refreshPermissions()
            }
        } label: {
            Label("NativeWhisper", systemImage: controller.menuIconName)
        }
        .menuBarExtraStyle(.window)
    }
}
