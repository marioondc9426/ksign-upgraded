//
//  CertificateWatcher.swift
//  Ksign
//
//  warns when a certificate is about to expire and when a new certificate with more time shows up
//  (then the signed apps can be signed again from Settings > Bulk Re-sign)
//

import Foundation
import CoreData

enum CertificateWatcher {
	static let alertsKey = "ksign.certExpiryAlerts"
	static let offerKey = "ksign.offerResignNewCert"
	/// uuid of the newest certificate Ksign offered to re-sign with (shown at the top of Bulk Re-sign)
	static let pendingKey = "ksign.resignOfferCertUUID"

	private static let _knownKey = "ksign.knownCertUUIDs"
	private static let _seededKey = "ksign.knownCertsSeeded"
	private static let _toldKey = "ksign.certExpiryTold"
	private static let _warnDays = 3.0

	static var alertsOn: Bool { UserDefaults.standard.object(forKey: alertsKey) as? Bool ?? true }
	static var offerOn: Bool { UserDefaults.standard.object(forKey: offerKey) as? Bool ?? true }

	static func allCertificates() -> [CertificatePair] {
		let request = NSFetchRequest<CertificatePair>(entityName: "CertificatePair")
		return (try? Storage.shared.context.fetch(request)) ?? []
	}

	/// signed apps whose certificate is missing or ends before `cert`
	static func appsWithOlderCertificate(than cert: CertificatePair) -> [Signed] {
		let request = NSFetchRequest<Signed>(entityName: "Signed")
		let apps = (try? Storage.shared.context.fetch(request)) ?? []
		guard let expiration = cert.expiration else { return apps }
		return apps.filter { app in
			if let own = app.certificate, VirtualCertificates.isVirtual(own) { return false }
			guard let current = app.certificate?.expiration else { return true }
			return current < expiration
		}
	}

	@MainActor
	static func scan() {
		let defaults = UserDefaults.standard
		let certificates = allCertificates()
		let now = Date()
		let valid = certificates.filter { !VirtualCertificates.isVirtual($0) && $0.revoked != true && ($0.expiration ?? .distantPast) > now }

		// 1. expiring soon, once per certificate per day
		if alertsOn {
			var told = defaults.dictionary(forKey: _toldKey) as? [String: String] ?? [:]
			let today = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: now))
			for cert in valid {
				guard let uuid = cert.uuid, let expiration = cert.expiration else { continue }
				let left = expiration.timeIntervalSince(now)
				guard left <= _warnDays * 86400, told[uuid] != today else { continue }
				told[uuid] = today

				let days = max(Int(ceil(left / 86400)), 0)
				UpdateManager.notify(
					title: .localized("Certificate expiring"),
					body: String(format: .localized("%@ ends in %lld days. Sign your apps again with another certificate in Settings > Bulk Re-sign"), cert.nickname ?? .localized("Unknown"), days),
					id: "ksign.certExpiry.\(uuid)"
				)
			}
			defaults.set(told, forKey: _toldKey)
		}

		// 2. a certificate that was not here before, with more time than what the signed apps have
		let known = Set(defaults.stringArray(forKey: _knownKey) ?? [])
		let current = Set(certificates.compactMap { $0.uuid })
		defaults.set(Array(current), forKey: _knownKey)

		guard defaults.bool(forKey: _seededKey) else {
			defaults.set(true, forKey: _seededKey)   // first run: everything already here is not new
			return
		}
		guard offerOn else { return }

		let fresh = valid.filter { !known.contains($0.uuid ?? "") }
		guard let best = fresh.max(by: { ($0.expiration ?? .distantPast) < ($1.expiration ?? .distantPast) }) else { return }

		let outdated = appsWithOlderCertificate(than: best)
		guard !outdated.isEmpty else { return }

		defaults.set(best.uuid, forKey: pendingKey)
		UpdateManager.notify(
			title: .localized("New certificate"),
			body: String(format: .localized("%lld apps can be signed again with %@. Go to Settings > Bulk Re-sign"), outdated.count, best.nickname ?? .localized("Unknown")),
			id: "ksign.newCert"
		)
	}
}
