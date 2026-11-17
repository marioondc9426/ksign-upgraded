//
//  UpdateManager.swift
//  Ksign
//
//  outdated apps (library vs sources), updating, and signing the update with the previous settings
//

import Foundation
import AltSourceKit
import UserNotifications

struct OutdatedApp: Identifiable {
	/// bundle identifier
	let id: String
	let app: ASRepository.App
	let source: ASRepository
	let localVersion: String
	let newVersion: String
	var hasProfile: Bool { SignProfiles.profile(for: id) != nil }
}

final class UpdateManager: ObservableObject {
	static let shared = UpdateManager()

	static let autoSignKey = "ksign.autoSignUpdates"
	static let notifyKey = "ksign.notifyUpdates"

	/// setting: sign updates with the previous settings as soon as they finish downloading
	static var autoSign: Bool { UserDefaults.standard.object(forKey: autoSignKey) as? Bool ?? true }

	/// download id -> bundle identifier that must be signed after it is imported
	private var _pendingSign: [String: String] = [:]
	/// bundle identifiers waiting for their turn (signing copies whole apps, one at a time)
	private var _signQueue: [String] = []
	private var _isSigning = false

	// MARK: Finding updates
	/// apps in `repos` that are newer than the copy in the library (matched by bundle identifier)
	static func outdated(in repos: [ASRepository]) -> [OutdatedApp] {
		var best: [String: OutdatedApp] = [:]

		for repo in repos {
			for app in repo.apps {
				guard
					let bundleID = app.id, !bundleID.isEmpty,
					let version = app.currentVersion, !version.isEmpty,
					app.currentDownloadUrl != nil,
					let local = Storage.shared.libraryVersion(for: bundleID),
					Storage.isNewer(version, than: local)
				else { continue }

				if let existing = best[bundleID], !Storage.isNewer(version, than: existing.newVersion) { continue }
				best[bundleID] = OutdatedApp(id: bundleID, app: app, source: repo, localVersion: local, newVersion: version)
			}
		}

		return best.values.sorted {
			($0.app.currentName).localizedCaseInsensitiveCompare($1.app.currentName) == .orderedAscending
		}
	}

	// MARK: Updating
	/// download the new version; it is signed afterwards when the setting is on and the app was signed before
	@MainActor
	func start(_ app: ASRepository.App) {
		guard let url = app.currentDownloadUrl else { return }
		let id = app.currentUniqueId

		if Self.autoSign, let bundleID = app.id, SignProfiles.profile(for: bundleID) != nil {
			_pendingSign[id] = bundleID
		}
		_ = DownloadManager.shared.startDownload(from: url, id: id)
	}

	@MainActor
	func updateAll(_ list: [OutdatedApp]) {
		list.forEach { start($0.app) }
	}

	/// called by DownloadManager when a download was extracted into the library
	@MainActor
	func importFinished(downloadID: String, error: Error?) {
		guard let bundleID = _pendingSign.removeValue(forKey: downloadID) else { return }
		guard error == nil else { return }
		_signQueue.append(bundleID)
		_signNext()
	}

	@MainActor
	private func _signNext() {
		guard !_isSigning, !_signQueue.isEmpty else { return }
		let bundleID = _signQueue.removeFirst()

		guard
			let profile = SignProfiles.profile(for: bundleID),
			let imported = Storage.shared.newestImported(bundleID: bundleID)
		else {
			_signNext()
			return
		}

		var options = profile.options
		// the new version number must come from the app itself, not from the old signing
		options.appVersion = nil
		AppSyncSupport.apply(&options)

		var certificate: CertificatePair?
		if let uuid = profile.certificateUUID {
			certificate = Storage.shared.certificate(withUUID: uuid)
		}

		let name = imported.name ?? bundleID
		let needsCertificate = !options.doAdhocSigning && !options.onlyModify
		guard !needsCertificate || certificate != nil else {
			Self.notify(title: .localized("Update"), body: String(format: .localized("%@ was updated but its certificate is gone, sign it manually"), name))
			_signNext()
			return
		}

		_isSigning = true
		FR.signPackageFile(imported, using: options, icon: nil, certificate: certificate) { [weak self] error in
			Task { @MainActor in
				guard let self else { return }
				self._isSigning = false
				if let error {
					Self.notify(title: .localized("Update"), body: "\(name): \(error.localizedDescription)")
				} else {
					SignProfiles.save(SignProfile(options: profile.options, certificateUUID: profile.certificateUUID, version: imported.version, date: Date()), for: bundleID)
					Self.notify(title: .localized("Update"), body: String(format: .localized("%@ updated and signed"), name))
				}
				self._signNext()
			}
		}
	}

	// MARK: Notifications
	static func notify(title: String, body: String, id: String = UUID().uuidString) {
		let content = UNMutableNotificationContent()
		content.title = title
		content.body = body
		content.sound = .default
		let request = UNNotificationRequest(
			identifier: id,
			content: content,
			trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
		)
		UNUserNotificationCenter.current().add(request)
	}
}
