//
//  SigningHistory.swift
//  Ksign
//
//  what was signed, with which certificate and options, and if it worked (with a Redo button)
//

import Foundation
import CoreData

struct SigningHistoryEntry: Codable, Identifiable {
	var id = UUID().uuidString
	var date = Date()
	var name: String
	var version: String?
	var identifier: String?
	/// uuid of the app that was signed (the library copy it came from)
	var sourceUUID: String?
	var sourceIsSigned: Bool
	var certificateUUID: String?
	var certificateName: String?
	var presetName: String?
	var success: Bool
	var error: String?
	var options: Options
}

enum SigningHistory {
	private static let _key = "ksign.signingHistory"
	private static let _limit = 100

	/// set by Quick Sign so the entry knows which preset was used
	static var pendingPresetName: String?

	static func all() -> [SigningHistoryEntry] {
		guard
			let data = UserDefaults.standard.data(forKey: _key),
			let decoded = try? JSONDecoder().decode([SigningHistoryEntry].self, from: data)
		else { return [] }
		return decoded
	}

	private static func _save(_ entries: [SigningHistoryEntry]) {
		if let data = try? JSONEncoder().encode(entries) {
			UserDefaults.standard.set(data, forKey: _key)
		}
	}

	static func record(app: AppInfoPresentable, options: Options, certificate: CertificatePair?, error: Error?) {
		let adhoc = options.doAdhocSigning || options.onlyModify
		let entry = SigningHistoryEntry(
			name: options.appName ?? app.name ?? "?",
			version: options.appVersion ?? app.version,
			identifier: options.appIdentifier ?? app.identifier,
			sourceUUID: app.uuid,
			sourceIsSigned: app.isSigned,
			certificateUUID: adhoc ? nil : certificate?.uuid,
			certificateName: adhoc ? "ad-hoc" : certificate?.nickname,
			presetName: pendingPresetName,
			success: error == nil,
			error: error?.localizedDescription,
			options: options
		)
		pendingPresetName = nil

		var entries = all()
		entries.insert(entry, at: 0)
		if entries.count > _limit { entries = Array(entries.prefix(_limit)) }
		_save(entries)
	}

	static func clear() {
		UserDefaults.standard.removeObject(forKey: _key)
	}

	/// the library app an entry was made from (nil when it was deleted since)
	static func sourceApp(for entry: SigningHistoryEntry) -> AppInfoPresentable? {
		guard let uuid = entry.sourceUUID else { return nil }
		let context = Storage.shared.context
		if entry.sourceIsSigned {
			let request = NSFetchRequest<Signed>(entityName: "Signed")
			request.predicate = NSPredicate(format: "uuid == %@", uuid)
			request.fetchLimit = 1
			return try? context.fetch(request).first
		} else {
			let request = NSFetchRequest<Imported>(entityName: "Imported")
			request.predicate = NSPredicate(format: "uuid == %@", uuid)
			request.fetchLimit = 1
			return try? context.fetch(request).first
		}
	}
}
