//
//  Server.swift
//  feather
//
//  Created by samara on 22.08.2024.
//  Copyright © 2024 Lakr Aream. All Rights Reserved.
//  ORIGINALLY LICENSED UNDER GPL-3.0, MODIFIED FOR USE FOR FEATHER
//

import Foundation
import Vapor
import NIOSSL
import NIOTLS
import SwiftUI
import IDeviceSwift

// MARK: - Class
class ServerInstaller: Identifiable, ObservableObject {
	let id = UUID()
	let port = Int.random(in: 4000...8000)
	private var _needsShutdown = false
	
	var packageUrl: URL?
	var app: AppInfoPresentable
	@ObservedObject var viewModel: InstallerStatusViewModel
	private let _server: Application

	init(app: AppInfoPresentable, viewModel: InstallerStatusViewModel) throws {
		self.app = app
		self.viewModel = viewModel
		self._server = try Self.setupApp(port: port)
		
		try _configureRoutes()
		try _server.server.start()
		_needsShutdown = true
	}
	
	deinit {
		_shutdownServer()
	}
		
	private func _configureRoutes() throws {
		_server.get("*") { [weak self] req in
			guard let self else { return Response(status: .badGateway) }
			switch req.url.path {
			case plistEndpoint.path:
				self._updateStatus(.sendingManifest)
				return Response(status: .ok, version: req.version, headers: [
					"Content-Type": "text/xml",
				], body: .init(data: installManifestData))
			case displayImageSmallEndpoint.path:
				return Response(status: .ok, version: req.version, headers: [
					"Content-Type": "image/png",
				], body: .init(data: displayImageSmallData))
			case displayImageLargeEndpoint.path:
				return Response(status: .ok, version: req.version, headers: [
					"Content-Type": "image/png",
				], body: .init(data: displayImageLargeData))
			case payloadEndpoint.path:
				guard let packageUrl = packageUrl else {
					return Response(status: .notFound)
				}
				
				self._updateStatus(.sendingPayload)
				
				return req.fileio.streamFile(
					at: packageUrl.path
				) { result in
                    switch result {
                    case .success:
                        self._updateStatus(.installing)
                    case .failure(let error):
                        self._updateStatus(.broken(error))
                    }
				}
			case "/install":
				var headers = HTTPHeaders()
				headers.add(name: .contentType, value: "text/html")
				return Response(status: .ok, headers: headers, body: .init(string: self.html))
			default:
				return Response(status: .notFound)
			}
		}
	}
	
	/// opens the system install prompt (itms-services). Fully Local uses the manifest served here,
	/// Semi Local uses the externally generated one. If iOS refuses to open the link, `fallback` shows the install page in Safari.
	func presentInstall(fallback: @escaping () -> Void) {
		let link = ServerInstaller.getServerMethod() == 0 ? iTunesLink : iTunesLinkExternal
		guard let url = URL(string: link) else {
			fallback()
			return
		}
		
		DispatchQueue.main.async {
			UIApplication.shared.open(url, options: [:]) { opened in
				if !opened { fallback() }
			}
		}
	}
	
	private func _shutdownServer() {
		guard _needsShutdown else { return }
		
		_needsShutdown = false
		_server.server.shutdown()
		_server.shutdown()
	}
	
    private func _updateStatus(_ newStatus: InstallerStatusViewModel.InstallerStatus) {
		DispatchQueue.main.async {
			self.viewModel.status = newStatus
		}
	}
		
	/// 0 = Fully Local (https + backloop.dev certificate), 1 = Semi Local (http + external manifest)
	/// the settings screen defaults to Semi Local (1), so an unset value must be 1 too.
	/// `integer(forKey:)` returns 0 when the key was never written, which silently picked Fully Local
	/// (https + wildcard host) while the UI showed Semi Local: that is why the page never loaded.
	static func getConfiguredServerMethod() -> Int {
		(UserDefaults.standard.object(forKey: "Feather.serverMethod") as? Int) ?? 1
	}
	
	/// the method actually used: Fully Local needs a valid SSL certificate, so an expired one falls back to Semi Local
	static func getServerMethod() -> Int {
		let method = getConfiguredServerMethod()
		return (method == 0 && isSSLCertificateExpired()) ? 1 : method
	}
	
	// MARK: SSL certificate expiry
	/// expiry date of the certificate pack saved by `FR.downloadSSLCertificates` (nil when unknown)
	static func sslCertificateExpiry() -> Date? {
		guard let raw = UserDefaults.standard.string(forKey: "Feather.sslNotAfter") else { return nil }
		let withFraction = ISO8601DateFormatter()
		withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return withFraction.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
	}
	
	static func isSSLCertificateExpired() -> Bool {
		guard let date = sslCertificateExpiry() else { return false }
		return date < Date()
	}
	
	/// where the certificate pack (cert, key, common name, expiry) is downloaded from
	static let defaultServerPackURL = "https://backloop.dev/pack.json"
	
	static func getServerPackURL() -> String {
		let value = UserDefaults.standard.string(forKey: "Feather.serverPackUrl")?.trimmingCharacters(in: .whitespacesAndNewlines)
		return (value?.isEmpty == false) ? value! : defaultServerPackURL
	}
	
	static func getIPFix() -> Bool {
		UserDefaults.standard.bool(forKey: "Feather.ipFix")
	}
	
	static func setServerMethod(_ method: Int) {
		UserDefaults.standard.set(method, forKey: "Feather.serverMethod")
	}
	
	static func setIPFix(_ enabled: Bool) {
		UserDefaults.standard.set(enabled, forKey: "Feather.ipFix")
	}
}
