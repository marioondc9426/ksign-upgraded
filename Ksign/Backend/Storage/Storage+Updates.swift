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
	/// reads an in-memory index (see LibraryVersionIndex), so it is cheap enough to call for every row of a list
	func libraryVersion(for bundleID: String) -> String? {
		LibraryVersionIndex.shared.versions[bundleID]
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

// MARK: - Index
/// bundle identifier -> highest version in the library, rebuilt only after the library changed
/// (it used to be two Core Data fetches for every app of every source on every redraw, which froze the App Store)
final class LibraryVersionIndex {
	static let shared = LibraryVersionIndex()

	private let _lock = NSLock()
	private var _cache: [String: String]?

	private init() {
		NotificationCenter.default.addObserver(
			forName: .NSManagedObjectContextObjectsDidChange,
			object: Storage.shared.context,
			queue: nil
		) { [weak self] _ in self?.invalidate() }
	}

	func invalidate() {
		_lock.lock()
		_cache = nil
		_lock.unlock()
	}

	var versions: [String: String] {
		_lock.lock()
		if let cached = _cache {
			_lock.unlock()
			return cached
		}
		_lock.unlock()

		let built = _build()

		_lock.lock()
		_cache = built
		_lock.unlock()
		return built
	}

	private func _build() -> [String: String] {
		var best: [String: String] = [:]

		func consider(_ id: String?, _ version: String?) {
			guard let id, !id.isEmpty, let version, !version.isEmpty else { return }
			if let current = best[id] {
				if Storage.isNewer(version, than: current) { best[id] = version }
			} else {
				best[id] = version
			}
		}

		let context = Storage.shared.context
		context.performAndWait {
			for entity in ["Imported", "Signed"] {
				let request = NSFetchRequest<NSDictionary>(entityName: entity)
				request.resultType = .dictionaryResultType
				request.propertiesToFetch = ["identifier", "version"]
				for row in (try? context.fetch(request)) ?? [] {
					consider(row["identifier"] as? String, row["version"] as? String)
				}
			}
		}

		// signed copies with a custom bundle identifier still count as this app (see SignProfiles)
		for (id, profile) in SignProfiles.all() {
			consider(id, profile.version)
		}
		return best
	}
}
