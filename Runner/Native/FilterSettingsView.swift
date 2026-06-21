import SwiftUI

/// Settings tab: account access, display, interaction, and filtering options.
struct FilterSettingsView: View {
  @ObservedObject var preferences: E621Preferences
  @ObservedObject var credentialStore: E621CredentialStore
  @ObservedObject var deepSeekSettings: DeepSeekSettings
  let onApply: () -> Void

  @State private var showsLogin = false
  @State private var showsPINSetup = false

  var body: some View {
    NavigationStack {
      Form {
        Section("Account") {
          if credentialStore.credentials.isComplete {
            LabeledContent("Signed in as", value: credentialStore.credentials.username)
          }
          Button(LocalizedStringKey(credentialStore.credentials.isComplete ? "Change login" : "Sign in")) {
            NativeHaptics.selection()
            showsLogin = true
          }
        }

        Section("User") {
          NavigationLink {
            DenylistEditorView(preferences: preferences, onApply: onApply)
          } label: {
            Label {
              VStack(alignment: .leading, spacing: 2) {
                Text("Blacklist")
                if !preferences.denylist.isEmpty {
                  Text("\(preferences.denylist.count) rules active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
            } icon: {
              Image(systemName: "nosign")
            }
          }
        }

        Section("Appearance") {
          Picker("Theme", selection: $preferences.theme) {
            ForEach(NativeTheme.allCases) { theme in
              Text(theme.title).tag(theme)
            }
          }

          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Label("Tile size", systemImage: "crop")
              Spacer()
              Text("\(Int(preferences.tileSize))")
                .foregroundStyle(.secondary)
            }
            Slider(value: $preferences.tileSize, in: 100...400, step: 10)
          }

          Picker("Quilt", selection: $preferences.quilt) {
            ForEach(NativeGridQuilt.allCases) { quilt in
              Text(quilt.title).tag(quilt)
            }
          }
          Text(preferences.quilt.description)
            .font(.caption)
            .foregroundStyle(.secondary)

          Toggle(isOn: $preferences.showPostInfo) {
            Label("Post info", systemImage: "text.below.photo")
          }
        }

        Section("Interactions") {
          Toggle(isOn: $preferences.upvoteFavorites) {
            Label("Upvote favorites", systemImage: "arrow.up.heart")
          }

          Toggle(isOn: $preferences.muteVideos) {
            Label("Video muted", systemImage: preferences.muteVideos ? "speaker.slash" : "speaker.wave.2")
          }

          Picker("Video resolution", selection: $preferences.videoResolution) {
            ForEach(NativeVideoResolution.allCases) { resolution in
              Text(resolution.title).tag(resolution)
            }
          }
        }

        Section {
          Toggle(isOn: Binding(
            get: { preferences.appPin != nil },
            set: { enabled in
              NativeHaptics.selection()
              if enabled {
                showsPINSetup = true
              } else {
                preferences.appPin = nil
              }
            }
          )) {
            Label("PIN lock", systemImage: "lock")
          }

          Toggle(isOn: $preferences.biometricAuth) {
            Label("Biometric lock", systemImage: "faceid")
          }
          .disabled(preferences.appPin == nil)
        } header: {
          Text("Security")
        } footer: {
          Text("PIN is stored in Keychain. Biometric unlock uses the device's local authentication.")
        }

        Section {
          PasteableAPIKeyField(title: "DeepSeek API key", text: $deepSeekSettings.configuration.apiKey)

          LabeledContent("Model", value: DeepSeekTranslator.model)
        } header: {
          Text("DeepSeek Translation")
        } footer: {
          Text("Used to translate post descriptions and comments into Simplified Chinese. The key is stored in Keychain.")
        }
      }
      .navigationTitle("Settings")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Apply") {
            NativeHaptics.success()
            onApply()
          }
        }
      }
      .sheet(isPresented: $showsLogin) {
        CredentialsView(store: credentialStore) {
          showsLogin = false
          onApply()
        }
      }
      .sheet(isPresented: $showsPINSetup) {
        PINSetupView { pin in
          preferences.appPin = pin
          showsPINSetup = false
        } onCancel: {
          NativeHaptics.selection()
          showsPINSetup = false
        }
      }
    }
  }
}

struct PINSetupView: View {
  let onConfirm: (String) -> Void
  let onCancel: () -> Void

  @State private var pin = ""
  @State private var confirmation = ""
  @State private var errorMessage: String?

  private var canSave: Bool {
    pin.count >= 4 && pin == confirmation
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          SecureField("Enter new PIN", text: $pin)
            .keyboardType(.numberPad)
          SecureField("Confirm new PIN", text: $confirmation)
            .keyboardType(.numberPad)
          if let errorMessage {
            Text(errorMessage)
              .font(.caption)
              .foregroundStyle(.red)
          }
        } footer: {
          Text("Use at least 4 digits.")
        }
      }
      .navigationTitle("PIN lock")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            NativeHaptics.selection()
            onCancel()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            guard pin.count >= 4 else {
              errorMessage = "PIN must be at least 4 digits."
              NativeHaptics.error()
              return
            }
            guard pin == confirmation else {
              errorMessage = "PINs do not match."
              NativeHaptics.error()
              return
            }
            NativeHaptics.success()
            onConfirm(pin)
          }
          .disabled(!canSave)
        }
      }
    }
  }
}

struct DenylistEditorView: View {
  @ObservedObject var preferences: E621Preferences
  let onApply: () -> Void

  var body: some View {
    Form {
      Section {
        TextEditor(text: $preferences.denylistText)
          .font(.system(.body, design: .monospaced))
          .frame(minHeight: 260)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
      } footer: {
        Text("One rule per line. Matching posts are hidden from browse results. Supports tags, -tag, ~tag, rating:e, type:webm, and comments after #.")
      }

      Section {
        Button("Clear blacklist", role: .destructive) {
          preferences.denylistText = ""
          NativeHaptics.warning()
          onApply()
        }
        .disabled(preferences.denylistText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .navigationTitle("Blacklist")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Apply") {
          NativeHaptics.success()
          onApply()
        }
      }
    }
  }
}
