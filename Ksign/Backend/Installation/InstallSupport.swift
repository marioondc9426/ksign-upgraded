//
//  InstallSupport.swift
//  Ksign
//
//  TrollStore (CoreTrust) and AppSync support: what this device can do and how to use it
//

import Foundation
import UIKit

enum TrollStoreSupport {
	static let method = 2   // value of "Feather.installationMethod"

	/// TrollStore's CoreTrust bug exists on iOS 14.0 up to 16.6.1, 16.7 RC and 17.0 (fixed in 17.0.1)
	static var coreTrustWorks: Bool {
		let v = ProcessInfo.processInfo.operatingSystemVersion
		return v.majorVersion < 17 || (v.majorVersion == 17 && v.minorVersion == 0 && v.patchVersion == 0)
	}

	/// needs `apple-magnifier` in LSApplicationQueriesSchemes
	static var isInstalled: Bool {
		guard let url = URL(string: "apple-magnifier://") else { return false }
		return UIApplication.shared.canOpenURL(url)
	}

	/// if the saved method is TrollStore but this iOS cannot do it, go back to the server method
	static func sanitizeMethod() {
		let key = "Feather.installationMethod"
		if UserDefaults.standard.integer(forKey: key) == method, !coreTrustWorks {
			UserDefaults.standard.set(0, forKey: key)
		}
	}

	/// opens the share sheet with the ipa, TrollStore shows up there as "Open in TrollStore"
	@MainActor
	static func send(_ packages: [URL]) {
		UIActivityViewController.show(activityItems: packages)
	}
}

enum AppSyncSupport {
	static let skipKey = "ksign.appSyncSkipSigning"

	/// AppSync Unified is a jailbreak tweak, so it can only be seen on a jailbroken device
	static var isInstalled: Bool {
		[
			"/var/jb/Library/MobileSubstrate/DynamicLibraries/AppSyncUnified-installd.dylib",
			"/Library/MobileSubstrate/DynamicLibraries/AppSyncUnified-installd.dylib",
			"/var/jb/usr/lib/TweakInject/AppSyncUnified-installd.dylib",
			"/usr/lib/TweakInject/AppSyncUnified-installd.dylib"
		].contains { FileManager.default.fileExists(atPath: $0) }
	}

	/// setting: sign with a fake (ad-hoc) signature, no certificate needed.
	/// AppSync Unified makes installd accept it, but the binary still needs a signature, so "only modify" would not work
	static var shouldSkipSigning: Bool {
		UserDefaults.standard.bool(forKey: skipKey) || JailbreakDetector.blocksCertificates
	}

	/// turns `options` into "ad-hoc sign, no certificate" when the setting is on
	static func apply(_ options: inout Options) {
		guard shouldSkipSigning else { return }
		options.doAdhocSigning = true
		options.onlyModify = false
		// the random suffix only exists to dodge PPQ checks of real certificates
		options.ppqProtection = false
	}
}
