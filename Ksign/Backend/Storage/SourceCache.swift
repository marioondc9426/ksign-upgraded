//
//  SourceCache.swift
//  Ksign
//
//  keeps the last downloaded copy of every source on disk, so the App Store shows its apps
//  at once when the app opens and the network refresh only replaces them afterwards
//

import Foundation
import CryptoKit
import AltSourceKit

enum SourceCache {
	private static let _directory: URL = {
		let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
			.appendingPathComponent("SourceCache", isDirectory: true)
		try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
		return base
	}()

	private static func _file(for url: URL) -> URL {
		let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
		let name = digest.map { String(format: "%02x", $0) }.joined()
		return _directory.appendingPathComponent(name + ".json")
	}

	static func save(_ data: Data, for url: URL) {
		try? data.write(to: _file(for: url), options: .atomic)
	}

	static func load(_ url: URL) -> ASRepository? {
		guard let data = try? Data(contentsOf: _file(for: url)) else { return nil }
		return try? JSONDecoder().decode(ASRepository.self, from: data)
	}

	static func remove(_ url: URL) {
		try? FileManager.default.removeItem(at: _file(for: url))
	}

	/// size of the whole cache, for the storage screen
	static func size() -> Int64 {
		let files = (try? FileManager.default.contentsOfDirectory(at: _directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
		return files.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
	}

	static func clear() {
		let files = (try? FileManager.default.contentsOfDirectory(at: _directory, includingPropertiesForKeys: nil)) ?? []
		files.forEach { try? FileManager.default.removeItem(at: $0) }
	}
}
