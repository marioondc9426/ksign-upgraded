//
//  Storage+Updates.swift
//  Ksign
//
//  finds out if an app in a source is newer than the one in your library
//

import CoreData

extension Storage {
	/// highest version of this bundle identifier in the library (imported or signed)
	/// the match is by bundle identifier only, never by name
	func libraryVersion(for bundleID: String) -> String? {
		var best: String?
		func consider(_ v: String?) {
			guard let v, !v.isEmpty else { return }
			if best == nil || Self.isNewer(v, than: best!) { best = v }
		}

		for entity in ["Imported", "Signed"] {
			let request = NSFetchRequest<NSManagedObject>(entityName: entity)
			request.predicate = NSPredicate(format: "identifier == %@", bundleID)
			guard let rows = try? context.fetch(request) else { continue }
			rows.forEach { consider($0.value(forKey: "version") as? String) }
		}

		// signed copies with a custom bundle identifier still count as this app (see SignProfiles)
		consider(SignProfiles.profile(for: bundleID)?.version)
		return best
	}

	/// true when `candidate` is a higher version than `installed` (1.10 > 1.9)
	static func isNewer(_ candidate: String, than installed: String) -> Bool {
		candidate.trimmingCharacters(in: .whitespaces)
			.compare(installed.trimmingCharacters(in: .whitespaces), options: .numeric) == .orderedDescending
	}

	/// source version is newer than the library copy of the same bundle identifier
	func hasUpdate(bundleID: String?, sourceVersion: String?) -> Bool {
		guard
			let bundleID, !bundleID.isEmpty,
			let sourceVersion, !sourceVersion.isEmpty,
			let local = libraryVersion(for: bundleID)
		else { return false }
		return Self.isNewer(sourceVersion, than: local)
	}

	/// newest imported (unsigned) copy of a bundle identifier
	func newestImported(bundleID: String) -> Imported? {
		let request = NSFetchRequest<Imported>(entityName: "Imported")
		request.predicate = NSPredicate(format: "identifier == %@", bundleID)
		request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
		request.fetchLimit = 1
		return try? context.fetch(request).first
	}

	func certificate(withUUID uuid: String) -> CertificatePair? {
		let request = NSFetchRequest<CertificatePair>(entityName: "CertificatePair")
		request.predicate = NSPredicate(format: "uuid == %@", uuid)
		request.fetchLimit = 1
		return try? context.fetch(request).first
	}
}
