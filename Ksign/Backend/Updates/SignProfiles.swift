//
//  SignProfiles.swift
//  Ksign
//
//  remembers how each app was signed (options + certificate) so an update
//  can be signed again the same way without opening the signing screen
//

import Foundation

struct SignProfile: Codable {
	var options: Options
	/// uuid of the CertificatePair used (nil = adhoc / only modify)
	var certificateUUID: String?
	/// version of the app that was signed (the original one, before any custom version)
	var version: String?
	var date: Date
}

enum SignProfiles {
	private static let _key = "ksign.signProfiles"

	/// bundle identifier of the original app -> how it was signed last time
	static func all() -> [String: SignProfile] {
		guard
			let data = UserDefaults.standard.data(forKey: _key),
			let decoded = try? JSONDecoder().decode([String: SignProfile].self, from: data)
		else { return [:] }
		return decoded
	}

	static func profile(for bundleID: String) -> SignProfile? {
		all()[bundleID]
	}

	static func save(_ profile: SignProfile, for bundleID: String) {
		var current = all()
		current[bundleID] = profile
		if let data = try? JSONEncoder().encode(current) {
			UserDefaults.standard.set(data, forKey: _key)
		}
	}

	static func remove(_ bundleID: String) {
		var current = all()
		current.removeValue(forKey: bundleID)
		if let data = try? JSONEncoder().encode(current) {
			UserDefaults.standard.set(data, forKey: _key)
		}
	}
}
