import SwiftUI

struct ConfigurationView: View {
    @ObservedObject var controller: MenuBarController
    @State private var apiKeyDraft: String = ""
    @State private var saveMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Configuration")
                .font(.system(size: 20, weight: .semibold))

            Text("Set your OpenAI API key and verify required permissions.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("OpenAI API Key")
                    .font(.system(size: 13, weight: .semibold))

                SecureField("sk-...", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 8) {
                    Button("Save API Key") {
                        controller.saveAPIKey(apiKeyDraft)
                        saveMessage = "API key saved on this Mac."
                    }

                    if let saveMessage {
                        Text(saveMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Status: \(controller.apiKeyConfigured ? "Configured" : "Not configured")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Permissions")
                    .font(.system(size: 13, weight: .semibold))

                permissionBlock(
                    title: "Microphone",
                    state: controller.permissionSnapshot.microphone,
                    route: "System Settings -> Privacy & Security -> Microphone",
                    actionTitle: "Open Microphone Settings",
                    action: {
                        controller.openSystemSettings(.microphone)
                    }
                )

                permissionBlock(
                    title: "Accessibility",
                    state: controller.permissionSnapshot.accessibility,
                    route: "System Settings -> Privacy & Security -> Accessibility",
                    actionTitle: "Open Accessibility Settings",
                    action: {
                        controller.openSystemSettings(.accessibility)
                    }
                )

                permissionBlock(
                    title: "Input Monitoring",
                    state: controller.permissionSnapshot.inputMonitoring,
                    route: "System Settings -> Privacy & Security -> Input Monitoring",
                    actionTitle: "Open Input Monitoring Settings",
                    action: {
                        controller.openSystemSettings(.inputMonitoring)
                    }
                )
            }

            Divider()

            HStack(spacing: 8) {
                Button("Test Permissions") {
                    controller.testPermissions()
                }

                Button("Refresh") {
                    controller.refreshPermissions()
                }

                Spacer()

                Text("Overall Status: \(controller.statusText)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(minWidth: 540, minHeight: 500)
        .onAppear {
            controller.refreshPermissions()
            apiKeyDraft = controller.currentAPIKey()
            saveMessage = nil
        }
    }

    @ViewBuilder
    private func permissionBlock(
        title: String,
        state: PermissionState,
        route: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title): \(controller.permissionLabel(for: state))")
                .font(.system(size: 12, weight: .medium))

            Text("Navigate: \(route)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Button(actionTitle, action: action)
                .font(.system(size: 11))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
