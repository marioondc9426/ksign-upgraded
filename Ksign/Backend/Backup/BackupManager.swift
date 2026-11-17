//
//  BackupManager.swift
//  Ksign
//
//  backup and restore of your sources and certificates in one zip file
//  the zip holds your certificates and their passwords in plain text, keep it private
//

import Foundation
import CoreData
import ZIPFoundation

enum BackupError: LocalizedError {
	case invalidBackup

	var errorDescription: String? {
		switch self {
		case .invalidBackup: return String.localized("This is not a Ksign backup.")
		}
	}
}

struct BackupSummary {
	var sources = 0
	var certificates = 0
	var skipped = 0
}

enum BackupManager {
	private struct Manifest: Codable {
		var version: Int
		var date: Date
		var sources: [String]
		var certificates: [CertEntry]
	}

	private struct CertEntry: Codable {
		var nickname: String?
		var password: String?
		var folder: String
		var p12: String
		var provision: String
	}

	/// certificates that ship inside the app (signing-assets) are not exported
	private static func _bundledCertificateNames() -> Set<String> {
		guard
			let url = Bundle.main.url(forResource: "signing-assets", withExtension: nil),
			let items = try? FileManager.default.contentsOfDirectory(atPath: url.path)
		else { return [] }
		return Set(items)
	}

	// MARK: Export
	/// builds the zip and returns its location (in the temporary directory)
	@MainActor
	static func export() throws -> URL {
		let fm = FileManager.default
		let work = fm.temporaryDirectory.appendingPathComponent("KsignBackup_\(UUID().uuidString)", isDirectory: true)
		try fm.createDirectory(at: work, withIntermediateDirectories: true)
		defer { try? fm.removeItem(at: work) }

		let context = Storage.shared.context

		let sources = (try? context.fetch(AltSource.fetchRequest())) ?? []
		let sourceURLs = sources.compactMap { $0.sourceURL?.absoluteString }

		let bundled = _bundledCertificateNames()
		let certs = (try? context.fetch(CertificatePair.fetchRequest())) ?? []
		var entries: [CertEntry] = []

		for (index, cert) in certs.enumerated() {
			if let name = cert.nickname, bundled.contains(name) { continue }
			guard
				let p12 = Storage.shared.getFile(.certificate, from: cert),
				let provision = Storage.shared.getFile(.provision, from: cert)
			else { continue }

			let folder = "certs/\(index)"
			let dir = work.appendingPathComponent(folder, isDirectory: true)
			try fm.createDirectory(at: dir, withIntermediateDirectories: true)
			try fm.copyItem(at: p12, to: dir.appendingPathComponent(p12.lastPathComponent))
			try fm.copyItem(at: provision, to: dir.appendingPathComponent(provision.lastPathComponent))

			entries.append(CertEntry(
				nickname: cert.nickname,
				password: cert.password,
				folder: folder,
				p12: p12.lastPathComponent,
				provision: provision.lastPathComponent
			))
		}

		let manifest = Manifest(version: 1, date: Date(), sources: sourceURLs, certificates: entries)
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		encoder.dateEncodingStrategy = .iso8601
		try encoder.encode(manifest).write(to: work.appendingPathComponent("backup.json"))

		let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
		let zip = fm.temporaryDirectory.appendingPathComponent("Ksign-backup-\(stamp).zip")
		try? fm.removeItem(at: zip)
		try fm.zipItem(at: work, to: zip, shouldKeepParent: false)
		return zip
	}

	// MARK: Restore
	/// adds what is in the backup and is not here yet (nothing is replaced or deleted)
	@MainActor
	static func restore(from file: URL) async throws -> BackupSummary {
		let fm = FileManager.default
		let work = fm.temporaryDirectory.appendingPathComponent("KsignRestore_\(UUID().uuidString)", isDirectory: true)
		try fm.createDirectory(at: work, withIntermediateDirectories: true)
		defer { try? fm.removeItem(at: work) }

		let scoped = file.startAccessingSecurityScopedResource()
		defer { if scoped { file.stopAccessingSecurityScopedResource() } }
		try fm.unzipItem(at: file, to: work)

		let manifestURL = work.appendingPathComponent("backup.json")
		guard let data = try? Data(contentsOf: manifestURL) else { throw BackupError.invalidBackup }
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		guard let manifest = try? decoder.decode(Manifest.self, from: data) else { throw BackupError.invalidBackup }

		var summary = BackupSummary()
		let context = Storage.shared.context

		// sources
		let have = Set(((try? context.fetch(AltSource.fetchRequest())) ?? []).compactMap { $0.sourceURL?.absoluteString })
		for url in manifest.sources {
			if have.contains(url) { summary.skipped += 1; continue }
			summary.sources += 1
			FR.handleSource(url) { }
		}

		// certificates (same nickname = already here)
		let haveNicknames = Set(((try? context.fetch(CertificatePair.fetchRequest())) ?? []).compactMap { $0.nickname })
		for entry in manifest.certificates {
			if let name = entry.nickname, haveNicknames.contains(name) { summary.skipped += 1; continue }

			let dir = work.appendingPathComponent(entry.folder, isDirectory: true)
			let p12 = dir.appendingPathComponent(entry.p12)
			let provision = dir.appendingPathComponent(entry.provision)
			guard fm.fileExists(atPath: p12.path), fm.fileExists(atPath: provision.path) else { continue }

			let error: Error? = await withCheckedContinuation { continuation in
				FR.handleCertificateFiles(
					p12URL: p12,
					provisionURL: provision,
					p12Password: entry.password ?? "",
					certificateName: entry.nickname ?? ""
				) { continuation.resume(returning: $0) }
			}
			if error == nil { summary.certificates += 1 }
		}

		return summary
	}
}
