import SwiftUI

/// Standard native login sheet for e621 HTTP Basic Auth credentials.
struct CredentialsView: View {
  @ObservedObject var store: E621CredentialStore
  let onDone: () -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section("Account") {
          TextField("Username", text: $store.credentials.username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          PasteableAPIKeyField(title: "API key", text: $store.credentials.apiKey)
        }

        Section {
          Link(destination: URL(string: "https://e621.net/api_keys")!) {
            Label("Open e621 API keys", systemImage: "key")
          }
        } footer: {
          Text("e621 API requests use HTTP Basic Auth with your username and API key.")
        }
      }
      .navigationTitle("e621 Login")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            NativeHaptics.selection()
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            NativeHaptics.success()
            dismiss()
            onDone()
          }
          .disabled(!store.credentials.isComplete)
        }
      }
    }
  }
}
