//
//  InstallationView.swift
//  Feather
//
//  Created by samara on 3.06.2025.
//

import SwiftUI
import NimbleViews

// MARK: - View
struct InstallationView: View {
    @AppStorage("Feather.installationMethod") private var _installationMethod: Int = 0
    @State private var _showMethodChangedAlert = false

    private var _installationMethods: [String] {
        var methods: [String] = [.localized("Server"), .localized("idevice")]
        if TrollStoreSupport.coreTrustWorks { methods.append(.localized("TrollStore")) }
        return methods
    }
    @AppStorage(AppSyncSupport.skipKey) private var _appSyncSkip = false

    private var _trollStoreStatus: String {
        if !TrollStoreSupport.coreTrustWorks { return String.localized("Not possible on this iOS") }
        return TrollStoreSupport.isInstalled ? String.localized("Installed") : String.localized("Possible, not installed")
    }
    
    // MARK: Body
    var body: some View {
        NBList(.localized("Installation")) {
            Section {
                Picker(.localized("Installation Type"), systemImage: "arrow.down.app", selection: $_installationMethod) {
                    ForEach(_installationMethods.indices, id: \.description) { index in
                        Text(_installationMethods[index]).tag(index)
                    }
                }
            } footer: {
                Text("Server (Recommended):\nUses a locally hosted server and itms-services:// to install applications.\n\nIDevice (advanced):\nUses a VPN and a pairing file. Writes to AFC and manually calls installd, while monitoring install progress by using a callback\nAdvantage: It is very reliable, does not need SSL certificates or a externally hosted server. Rather, works similarly to a computer.")
            }
            
            Section {
                LabeledContent(.localized("TrollStore (CoreTrust)")) {
                    Text(verbatim: _trollStoreStatus)
                        .foregroundStyle(.secondary)
                }
                LabeledContent(.localized("AppSync Unified")) {
                    Text(verbatim: AppSyncSupport.isInstalled ? String.localized("Found") : String.localized("Not found"))
                        .foregroundStyle(.secondary)
                }
                if AppSyncSupport.isInstalled {
                    Toggle(.localized("Skip signing (AppSync)"), isOn: $_appSyncSkip)
                }
            } header: {
                Text(.localized("This device"))
            } footer: {
                Text(.localized("TrollStore install sends the ipa to TrollStore, which installs it with a permanent signature (needs iOS 14.0 to 16.6.1 or 17.0 and TrollStore installed). With AppSync Unified on a jailbroken device the apps do not need a valid signature, so signing can be skipped."))
            }

            if _installationMethod == 0 {
                ServerView()
            } else if _installationMethod == 1 {
                TunnelView()
            }
        }
        .onChange(of: _installationMethod) { newValue in
            guard newValue == 1 else { return }
            _showMethodChangedAlert = true
        }
        .alert(.localized("Advanced Installation Method"), isPresented: $_showMethodChangedAlert) {
            Button(.localized("Switch Back"), role: .destructive) {
                _installationMethod = 0
            }
            Button(.localized("OK"), role: .cancel) {}
        } message: {
            Text(.localized("idevice warning"))
        }


        .animation(.default, value: _installationMethod)
    }
}

