//
//  StorageCleanupView.swift
//  Ksign
//
//  size of every app in the library, and a one-tap delete of the originals that were already signed
//

import SwiftUI
import CoreData
import NimbleViews

struct StorageCleanupView: View {
	@FetchRequest(
		entity: Imported.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \Imported.date, ascending: false)]
	) private var _imported: FetchedResults<Imported>

	@FetchRequest(
		entity: Signed.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \Signed.date, ascending: false)]
	) private var _signed: FetchedResults<Signed>

	@State private var _sizes: [String: Int64] = [:]
	@State private var _isMeasuring = false
	@State private var _confirmDelete = false

	/// downloaded apps that already have a signed copy (same identifier, or the signed one has the PPQ suffix)
	private var _alreadySigned: [Imported] {
		let signedIDs = _signed.compactMap { $0.identifier }
		return _imported.filter { imported in
			guard let id = imported.identifier else { return false }
			return signedIDs.contains { $0 == id || $0.hasPrefix(id + ".") }
		}
	}

	var body: some View {
		NBList(.localized("Storage")) {
			Section {
				LabeledContent(.localized("Downloaded Apps")) { Text(_total(_imported.compactMap { $0.uuid })) }
				LabeledContent(.localized("Signed Apps")) { Text(_total(_signed.compactMap { $0.uuid })) }
			}

			let cleanable = _alreadySigned
			Section {
				Button(role: .destructive) {
					_confirmDelete = true
				} label: {
					Label(
						String(format: .localized("Delete %lld originals already signed (%@)"), cleanable.count, _total(cleanable.compactMap { $0.uuid })),
						systemImage: "trash"
					)
				}
				.disabled(cleanable.isEmpty)
			} footer: {
				Text(.localized("Only downloaded apps that have a signed copy in the Signed tab. The signed copies are not touched."))
			}

			Section(.localized("Downloaded Apps")) {
				ForEach(_imported, id: \.uuid) { app in _row(app, uuid: app.uuid) }
					.onDelete { offsets in offsets.forEach { Storage.shared.deleteApp(for: _imported[$0]) } }
			}
			Section(.localized("Signed Apps")) {
				ForEach(_signed, id: \.uuid) { app in _row(app, uuid: app.uuid) }
					.onDelete { offsets in offsets.forEach { Storage.shared.deleteApp(for: _signed[$0]) } }
			}
		}
		.task { await _measure() }
		.confirmationDialog(.localized("Delete the originals?"), isPresented: $_confirmDelete, titleVisibility: .visible) {
			Button(.localized("Delete"), role: .destructive) {
				_alreadySigned.forEach { Storage.shared.deleteApp(for: $0) }
				Task { await _measure() }
			}
		} message: {
			Text(.localized("This cannot be undone."))
		}
	}

	@ViewBuilder
	private func _row(_ app: AppInfoPresentable, uuid: String?) -> some View {
		HStack {
			FRAppIconView(app: app, size: 38)
			VStack(alignment: .leading, spacing: 1) {
				Text(app.name ?? .localized("Unknown")).lineLimit(1)
				Text("\(app.version ?? "") • \(app.identifier ?? "")")
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
			Spacer()
			if let uuid, let size = _sizes[uuid] {
				Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
					.font(.footnote)
					.foregroundStyle(.secondary)
			} else if _isMeasuring {
				ProgressView()
			}
		}
	}

	private func _total(_ uuids: [String]) -> String {
		let sum = uuids.reduce(Int64(0)) { $0 + (_sizes[$1] ?? 0) }
		return ByteCountFormatter.string(fromByteCount: sum, countStyle: .file)
	}

	private func _measure() async {
		_isMeasuring = true
		let importedDirs = _imported.compactMap { app in app.uuid.map { ($0, FileManager.default.unsigned($0)) } }
		let signedDirs = _signed.compactMap { app in app.uuid.map { ($0, FileManager.default.signed($0)) } }
		let jobs = importedDirs + signedDirs

		let result: [String: Int64] = await Task.detached(priority: .utility) {
			var sizes: [String: Int64] = [:]
			for (uuid, url) in jobs {
				var total: Int64 = 0
				if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) {
					for case let file as URL in enumerator {
						total += Int64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
					}
				}
				sizes[uuid] = total
			}
			return sizes
		}.value

		_sizes = result
		_isMeasuring = false
	}
}
