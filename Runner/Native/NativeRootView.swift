import LocalAuthentication
import SwiftUI

/// App root: a standard native tab bar (Browse / Favorites / Settings), each tab
/// driving its own paged post feed. The e621 gold accent tints the whole UI.
struct NativeRootView: View {
  @StateObject private var credentialStore: E621CredentialStore
  @StateObject private var deepSeekSettings: DeepSeekSettings
  @StateObject private var preferences: E621Preferences
  @StateObject private var browseModel: PostsViewModel
  @StateObject private var favoritesModel: PostsViewModel
  @State private var selectedTab = 0

  init() {
    let store = E621CredentialStore()
    let deepSeek = DeepSeekSettings()
    let prefs = E621Preferences()
    _credentialStore = StateObject(wrappedValue: store)
    _deepSeekSettings = StateObject(wrappedValue: deepSeek)
    _preferences = StateObject(wrappedValue: prefs)
    _browseModel = StateObject(wrappedValue: PostsViewModel(credentialStore: store, preferences: prefs))
    _favoritesModel = StateObject(wrappedValue: PostsViewModel(credentialStore: store, preferences: prefs))
  }

  var body: some View {
    AppLockGate(preferences: preferences) {
      TabView(selection: $selectedTab) {
        BrowseView(
          model: browseModel,
          preferences: preferences,
          credentialStore: credentialStore,
          deepSeekSettings: deepSeekSettings,
          onSearchTag: searchTag
        )
          .tabItem { Label("Browse", systemImage: "square.grid.2x2") }
          .tag(0)

        FavoritesView(
          model: favoritesModel,
          preferences: preferences,
          credentialStore: credentialStore,
          deepSeekSettings: deepSeekSettings,
          onSearchTag: searchTag
        )
          .tabItem { Label("Favorites", systemImage: "heart") }
          .tag(1)

        FilterSettingsView(
          preferences: preferences,
          credentialStore: credentialStore,
          deepSeekSettings: deepSeekSettings,
          onApply: {
            browseModel.search()
            favoritesModel.search()
          }
        )
        .tabItem { Label("Settings", systemImage: "gearshape") }
        .tag(2)
      }
    }
    .tint(.e621Gold)
    .preferredColorScheme(preferences.theme.preferredColorScheme)
  }

  /// Tapping a tag anywhere searches it on the Browse tab and switches to it.
  private func searchTag(_ tag: String) {
    browseModel.search(tag: tag)
    selectedTab = 0
  }
}

private struct AppLockGate<Content: View>: View {
  @ObservedObject var preferences: E621Preferences
  let content: Content

  @State private var isLocked: Bool
  @State private var enteredPIN = ""
  @State private var errorMessage: String?
  @State private var triedBiometrics = false

  init(preferences: E621Preferences, @ViewBuilder content: () -> Content) {
    self.preferences = preferences
    self.content = content()
    _isLocked = State(initialValue: preferences.appPin != nil)
  }

  var body: some View {
    ZStack {
      content
        .opacity(isLocked ? 0 : 1)
        .allowsHitTesting(!isLocked)

      if isLocked {
        lockView
          .transition(.opacity)
      }
    }
    .onChange(of: preferences.appPin) { _, pin in
      isLocked = pin != nil
      enteredPIN = ""
      triedBiometrics = false
    }
    .onChange(of: preferences.biometricAuth) { _, _ in
      triedBiometrics = false
    }
    .task(id: isLocked) {
      if isLocked {
        await authenticateIfNeeded()
      }
    }
  }

  private var lockView: some View {
    VStack(spacing: 22) {
      Image(systemName: "lock.fill")
        .font(.system(size: 46, weight: .semibold))
        .foregroundStyle(Color.e621Gold)

      Text("Enter PIN")
        .font(.title2.weight(.semibold))

      SecureField("PIN", text: $enteredPIN)
        .keyboardType(.numberPad)
        .textContentType(.oneTimeCode)
        .multilineTextAlignment(.center)
        .font(.title3.monospacedDigit())
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(maxWidth: 260)
        .onSubmit(unlockWithPIN)

      if let errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
      }

      HStack(spacing: 12) {
        Button("Unlock", action: unlockWithPIN)
          .buttonStyle(.borderedProminent)
          .disabled(enteredPIN.isEmpty)

        if preferences.biometricAuth {
          Button {
            Task { await authenticateBiometrics() }
          } label: {
            Label("Biometric", systemImage: "faceid")
          }
          .buttonStyle(.bordered)
        }
      }
    }
    .padding(28)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemGroupedBackground).ignoresSafeArea())
  }

  private func unlockWithPIN() {
    guard enteredPIN == preferences.appPin else {
      NativeHaptics.error()
      errorMessage = "Incorrect PIN."
      enteredPIN = ""
      return
    }
    unlock()
  }

  private func unlock() {
    NativeHaptics.success()
    withAnimation(.easeInOut(duration: 0.18)) {
      isLocked = false
    }
    errorMessage = nil
    enteredPIN = ""
  }

  private func authenticateIfNeeded() async {
    guard preferences.biometricAuth, !triedBiometrics else { return }
    triedBiometrics = true
    await authenticateBiometrics()
  }

  private func authenticateBiometrics() async {
    let context = LAContext()
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
      await MainActor.run { NativeHaptics.warning() }
      await MainActor.run { errorMessage = "Biometric authentication is unavailable." }
      return
    }

    do {
      let success = try await context.evaluatePolicy(
        .deviceOwnerAuthenticationWithBiometrics,
        localizedReason: "Authenticate to unlock."
      )
      if success {
        await MainActor.run { unlock() }
      }
    } catch {
      await MainActor.run { NativeHaptics.error() }
      await MainActor.run { errorMessage = "Failed to authenticate." }
    }
  }
}
