//
//  Server+TLS.swift
//  feather
//
//  Created by samara on 22.08.2024.
//  Copyright © 2024 Lakr Aream. All Rights Reserved.
//  ORIGINALLY LICENSED UNDER GPL-3.0, MODIFIED FOR USE FOR FEATHER
//

import Foundation
import NIOSSL
import NIOTLS
import Vapor
import SystemConfiguration.CaptiveNetwork

// MARK: - Class extension: TLS/Setup
extension ServerInstaller {
	// MARK: Setup
	private static let env: Environment = {
		var env = try! Environment.detect()
		try! LoggingSystem.bootstrap(from: &env)
		return env
	}()
	
	static func setupApp(port: Int) throws -> Application {
		let app = Application(env)
		app.threadPool = .init(numberOfThreads: 1)
		
		if ServerInstaller.getServerMethod() != 1 {
			if let tls = try Self.tls() {
				app.http.server.configuration.tlsConfiguration = tls
			}
		}
		
		app.http.server.configuration.hostname = Self.sni
		app.http.server.configuration.tcpNoDelay = true
		app.http.server.configuration.address = .hostname("0.0.0.0", port: port)
		app.http.server.configuration.port = port
		app.routes.defaultMaxBodySize = "128mb"
		app.routes.caseInsensitive = false
		
		return app
	}
	
	// MARK: Files/IP
	/// host used in every URL of the install flow. It is computed on each access (it used to be a `static let`,
	/// so changing "Only use localhost" did nothing until the app was restarted).
	static var sni: String {
		let localhost = "127.0.0.1"
		
		if getServerMethod() == 1 {
			return !ServerInstaller.getIPFix()
			? (getLocalAddress() ?? localhost)
			: localhost
		} else {
			return hostFromCommonName(readCommonName()) ?? localhost
		}
	}
	
	/// the certificate is a wildcard ("*.backloop.dev"); a literal "*" is not a valid host, so use any subdomain
	/// (every *.backloop.dev name resolves to 127.0.0.1)
	static func hostFromCommonName(_ name: String?) -> String? {
		guard var name, !name.isEmpty else { return nil }
		if name.hasPrefix("*.") {
			name = "local." + name.dropFirst(2)
		}
		return name
	}
	
	static func tls() throws -> TLSConfiguration? {
		guard
			let crt = getUrl("server", ext: "crt"),
			let pem = getUrl("server", ext: "pem")
		else {
			return nil
		}
		
		return try TLSConfiguration.makeServerConfiguration(
			certificateChain: NIOSSLCertificate.fromPEMFile(crt.path).map {
				NIOSSLCertificateSource.certificate($0)
			},
			privateKey: .privateKey(
				try NIOSSLPrivateKey(file: pem.path, format: .pem)
			)
		)
	}
	
	static func readCommonName() -> String? {
		guard let url = getUrl("commonName", ext: "txt") else {
			return nil
		}
		
		return try? String(contentsOf: url, encoding: .utf8)
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}
}

extension ServerInstaller {
	static func getUrl(_ name: String, ext: String) -> URL? {
		let fileManager = FileManager.default
		
		let serverURL = URL.documentsDirectory.appendingPathComponent("App").appendingPathComponent("Server").appendingPathComponent("\(name).\(ext)")
		if fileManager.fileExists(atPath: serverURL.path) {
			return serverURL
		}
		
		let documentsURL = URL.documentsDirectory.appendingPathComponent("\(name).\(ext)")
		if fileManager.fileExists(atPath: documentsURL.path) {
			return documentsURL
		}
		
		let oldServerURL = URL.documentsDirectory.appendingPathComponent("Server").appendingPathComponent("\(name).\(ext)")
		if fileManager.fileExists(atPath: oldServerURL.path) {
			return oldServerURL
		}
		
		return Bundle.main.url(forResource: name, withExtension: ext)
	}
	
	static func getLocalAddress() -> String? {
		var wifi: String?
		var cellular: String?
		var ifaddr: UnsafeMutablePointer<ifaddrs>?
		
		if getifaddrs(&ifaddr) == 0 {
			var ptr = ifaddr
			while ptr != nil {
				let interface = ptr!.pointee
				let addrFamily = interface.ifa_addr.pointee.sa_family
				
				if addrFamily == UInt8(AF_INET) {
					let name = String(cString: interface.ifa_name)
					if name == "en0" || name == "pdp_ip0" {
						var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
						if getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
									   &hostname, socklen_t(hostname.count),
									   nil, socklen_t(0), NI_NUMERICHOST) == 0 {
							let value = String(cString: hostname)
							// the loop used to keep the LAST match, so a phone with Wi-Fi and a SIM ended up with the
							// cellular address, which Safari on the same phone cannot reach as a local server
							if name == "en0" { wifi = value } else { cellular = value }
						}
					}
				}
				ptr = ptr!.pointee.ifa_next
			}
			freeifaddrs(ifaddr)
		}
		
		// without Wi-Fi (mobile data only) use localhost: the cellular address is not reachable by Safari or installd
		_ = cellular
		return wifi
	}
}
