import AppKit
import SwiftUI

final class WhisperAnywhereAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct WhisperAnywhereApp: App {
    @NSApplicationDelegateAdaptor(WhisperAnywhereAppDelegate.self) private var appDelegate
    @StateObject private var controller = MenuBarController()

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 10) {
                Text("Status: \(controller.statusText)")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                Picker("Provider", selection: Binding(
                    get: { controller.selectedProvider },
                    set: { controller.setTranscriptionProvider($0) }
                )) {
                    Text("OpenAI").tag(TranscriptionProvider.openAI)
                    Text("Deepgram").tag(TranscriptionProvider.deepgram)
                }
                .pickerStyle(.inline)

                Divider()

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
            Label("Whisper Anywhere", systemImage: controller.menuIconName)
        }
        .menuBarExtraStyle(.window)
    }
}
