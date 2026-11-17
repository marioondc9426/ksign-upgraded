//
//  JailbreakDetector.swift
//  Ksign
//
//  detects a jailbroken device, and keeps the certificates out of it: on a jailbreak any tweak or
//  root process can read the app's files, so the (private) certificate is never used there and
//  everything is signed ad-hoc instead (AppSync accepts that)
//

import Foundation
import UIKit
import MachO

enum JailbreakDetector {
	static let policyKey = "ksign.noCertOnJailbreak"

	/// what was found (empty = not jailbroken). Checked once per launch
	static let reasons: [String] = _scan()

	static var isJailbroken: Bool { !reasons.isEmpty }

	/// setting, on by default
	static var policyOn: Bool { UserDefaults.standard.object(forKey: policyKey) as? Bool ?? true }

	/// true when certificates must not be used right now
	static var blocksCertificates: Bool { policyOn && isJailbroken }

	/// options that never ask for a certificate on a jailbroken device
	static func enforce(_ options: Options) -> Options {
		guard blocksCertificates, !options.onlyModify else { return options }
		var result = options
		result.doAdhocSigning = true
		return result
	}

	// MARK: Scan
	private static func _scan() -> [String] {
		#if targetEnvironment(simulator)
		return []
		#else
		var found: [String] = []
		let fm = FileManager.default

		// files a jailbreak leaves behind
		let paths = [
			"/Applications/Cydia.app", "/Applications/Sileo.app", "/Applications/Zebra.app", "/Applications/Installer.app",
			"/var/jb", "/private/preboot/procursus", "/var/binpack", "/.bootstrapped", "/.installed_unc0ver",
			"/Library/MobileSubstrate/MobileSubstrate.dylib", "/Library/MobileSubstrate/DynamicLibraries",
			"/usr/lib/TweakInject", "/usr/libexec/cydia", "/usr/sbin/sshd", "/usr/bin/ssh", "/bin/bash",
			"/etc/apt", "/var/lib/apt", "/var/lib/dpkg", "/var/lib/cydia", "/private/var/lib/apt"
		]
		for path in paths where fm.fileExists(atPath: path) {
			found.append(path)
		}

		// a stock iOS sandbox cannot write outside the app
		let probe = "/private/ksign-\(UUID().uuidString).txt"
		if (try? "x".write(toFile: probe, atomically: true, encoding: .utf8)) != nil {
			try? fm.removeItem(atPath: probe)
			found.append("writes outside the sandbox")
		}

		// injection libraries loaded into this very process
		let markers = ["substrate", "ellekit", "libhooker", "tweakinject", "substitute"]
		for index in 0..<_dyld_image_count() {
			guard let cName = _dyld_get_image_name(index) else { continue }
			let name = String(cString: cName).lowercased()
			if let marker = markers.first(where: { name.contains($0) }) {
				found.append("loaded \(marker)")
				break
			}
		}
		if getenv("DYLD_INSERT_LIBRARIES") != nil {
			found.append("DYLD_INSERT_LIBRARIES")
		}

		// package managers (needs the schemes in LSApplicationQueriesSchemes, only possible on the main thread)
		if Thread.isMainThread {
			for scheme in ["cydia", "sileo", "zbra", "installer"] {
				if let url = URL(string: "\(scheme)://package/com.example.package"), UIApplication.shared.canOpenURL(url) {
					found.append("\(scheme)://")
					break
				}
			}
		}
		return found
		#endif
	}
}
