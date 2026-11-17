//
//  VirtualCertificates.swift
//  Ksign
//
//  on a jailbroken device the certificate list gets two extra entries that are not real certificates:
//    TrollStore  (999 days)     signs ad-hoc and installs through TrollStore
//    AppSync     (until reboot) signs ad-hoc, AppSync Unified lets the device accept it
//  they hold no files and are never exported, backed up or used for anything but ad-hoc signing
//

import Foundation
import CoreData

enum VirtualCertificates {
	enum Kind: CaseIterable {
		case trollStore, appSync

		var uuid: String {
			switch self {
			case .trollStore: return "ksign.virtual.trollstore"
			case .appSync: return "ksign.virtual.appsync"
			}
		}
		var name: String {
			switch self {
			case .trollStore: return "TrollStore"
			case .appSync: return "AppSync"
			}
		}
	}

	static func kind(of cert: CertificatePair) -> Kind? {
		Kind.allCases.first { $0.uuid == cert.uuid }
	}

	static func isVirtual(_ cert: CertificatePair) -> Bool { kind(of: cert) != nil }

	/// text for the expiration pill (nil for real certificates)
	static func label(for cert: CertificatePair?) -> String? {
		guard let cert, let kind = kind(of: cert) else { return nil }
		switch kind {
		case .trollStore: return String(format: String.localized("%lld days"), 999)
		case .appSync: return String.localized("Until reboot")
		}
	}

	static func subtitle(for cert: CertificatePair) -> String? {
		guard let kind = kind(of: cert) else { return nil }
		switch kind {
		case .trollStore: return String.localized("No certificate, installs through TrollStore")
		case .appSync: return String.localized("No certificate, needs AppSync Unified")
		}
	}

	/// adds the entries on a jailbroken device and removes them anywhere else.
	/// they sort after the real certificates, so the selected certificate keeps its place in the list
	@MainActor
	static func sync() {
		let context = Storage.shared.context
		let all = CertificateWatcher.allCertificates()
		var changed = false

		for kind in Kind.allCases {
			let wanted: Bool
			switch kind {
			case .trollStore: wanted = JailbreakDetector.isJailbroken && TrollStoreSupport.coreTrustWorks
			case .appSync: wanted = JailbreakDetector.isJailbroken
			}
			let existing = all.first { $0.uuid == kind.uuid }

			if wanted {
				let expiration = kind == .trollStore
					? Calendar.current.date(byAdding: .day, value: 999, to: Date()) ?? Date.distantFuture
					: Calendar.current.date(byAdding: .day, value: 365, to: Date()) ?? Date.distantFuture
				let cert = existing ?? CertificatePair(context: context)
				cert.uuid = kind.uuid
				cert.nickname = kind.name
				cert.date = Date.distantPast
				cert.expiration = expiration
				cert.ppQCheck = false
				cert.revoked = false
				changed = true
			} else if let existing {
				context.delete(existing)
				changed = true
			}
		}

		if changed { Storage.shared.saveContext() }
	}

	/// what a signing with a virtual certificate does to the options
	static func enforce(_ options: Options, certificate: CertificatePair?) -> Options {
		guard let certificate, isVirtual(certificate), !options.onlyModify else { return options }
		var result = options
		result.doAdhocSigning = true
		result.ppqProtection = false
		return result
	}
}
