//
//  ServerView.swift
//  Feather
//
//  Created by samara on 6.05.2025.
//

import SwiftUI
import NimbleJSON
import NimbleViews

struct ServerView: View {
	@AppStorage("Feather.ipFix") private var _ipFix: Bool = false
	@AppStorage("Feather.serverMethod") private var _serverMethod: Int = 1
	
	private let _serverMethods: [String] = [
		.localized("Fully Local"), 
		.localized("Semi Local")
	]
	
	private let _dataService = NBFetchService()
	@AppStorage("Feather.serverPackUrl") private var _serverPackUrl: String = ServerInstaller.defaultServerPackURL
	
	var body: some View {
		Group {
			Section {
				Picker(.localized("Installation Type"), systemImage: "server.rack", selection: $_serverMethod) {
					ForEach(_serverMethods.indices, id: \.self) { index in
						Text(_serverMethods[index]).tag(index)
					}
				}
				Toggle(.localized("Only use localhost address"), systemImage: "lifepreserver", isOn: $_ipFix)
					.disabled(_serverMethod != 1)
			}
			
			if let expiry = ServerInstaller.sslCertificateExpiry() {
				Section {
					if expiry < Date() {
						Label(
							String(format: .localized("The SSL certificate expired on %@. Fully Local can not work until a new one is published, so Semi Local is used instead."), expiry.formatted(date: .abbreviated, time: .omitted)),
							systemImage: "exclamationmark.triangle"
						)
						.foregroundStyle(.orange)
					} else {
						Label(
							String(format: .localized("SSL certificate valid until %@"), expiry.formatted(date: .abbreviated, time: .omitted)),
							systemImage: "checkmark.seal"
						)
					}
				}
			}
			
			Section {
				TextField(.localized("Certificate pack URL"), text: $_serverPackUrl)
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled()
					.keyboardType(.URL)
				Button(.localized("Update SSL Certificates"), systemImage: "arrow.down.doc") {
					FR.downloadSSLCertificates(from: ServerInstaller.getServerPackURL()) { success in
						if !success {
							DispatchQueue.main.async {
								UIAlertController.showAlertWithOk(
									title: .localized("SSL Certificates"),
									message: .localized("Failed to download, check your internet connection and try again.")
								)
							}
						}
					}
				}
			}
		}
		.onChange(of: _serverMethod) { _ in
			UIAlertController.showAlertWithRestart(
				title: .localized("Restart Required"),
				message: .localized("These changes require a restart of the app")
			)
		}
	}
}
