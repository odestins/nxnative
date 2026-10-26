import SwiftUI
import AVFoundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum ChatPlatform {
    static func requestMicrophone() async -> Bool {
        #if os(macOS)
        return await AVCaptureDevice.requestAccess(for: .audio)
        #else
        return await AVAudioApplication.requestRecordPermission()
        #endif
    }
    @MainActor static func openMicrophoneSettings() {
        #if os(macOS)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        #else
        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
        #endif
    }
}

struct ChatAudioDevice: Identifiable, Equatable {
    let id: String
    let name: String
    static func decode(_ payload: [String: Any]) -> [Self] {
        var seen = Set<String>()
        return (payload["devices"] as? [[String: Any]] ?? []).compactMap { row in
            guard let id = row["id"] as? String, !id.isEmpty, id.count <= 4096,
                  let name = row["name"] as? String, !name.isEmpty, seen.insert(id).inserted else { return nil }
            return Self(id: id, name: name)
        }
    }
}

extension View {
    @ViewBuilder func chatVoiceMenuStyle() -> some View {
        #if os(macOS)
        menuStyle(.borderlessButton).menuIndicator(.hidden)
        #else
        self
        #endif
    }
    @ViewBuilder func chatInlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
    @ViewBuilder func chatInvitationInput() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never).autocorrectionDisabled()
        #else
        autocorrectionDisabled()
        #endif
    }
    @ViewBuilder func chatKeyboardDismiss() -> some View {
        #if os(iOS)
        scrollDismissesKeyboard(.interactively)
        #else
        self
        #endif
    }
    @ViewBuilder func chatSheetSizes() -> some View {
        #if os(iOS)
        presentationDetents([.medium, .large])
        #else
        frame(minWidth: 520, minHeight: 400)
        #endif
    }
}
