//
//  SigningHistoryView.swift
//  Ksign
//
//  everything that was signed, with a button to do it again
//

import SwiftUI
import NimbleViews

struct SigningHistoryView: View {
	@State private var _entries: [SigningHistoryEntry] = SigningHistory.all()
	@State private var _isRedoing = false
	@State private var _message: String?

	var body: some View {
		NBList(.localized("Signing History")) {
			if _entries.isEmpty {
				Section {
					Text(.localized("Nothing signed yet."))
						.foregroundStyle(.secondary)
				}
			}

			if let _message {
				Section { Text(_message).font(.footnote) }
			}

			Section {
				ForEach(_entries) { entry in
					VStack(alignment: .leading, spacing: 4) {
						HStack {
							Image(systemName: entry.success ? "checkmark.circle.fill" : "xmark.octagon.fill")
								.foregroundStyle(entry.success ? .green : .red)
							Text(entry.name).font(.headline)
							Spacer()
							Text(entry.date.formatted(date: .abbreviated, time: .shortened))
								.font(.caption)
								.foregroundStyle(.secondary)
						}
						Text("\(entry.version ?? "") • \(entry.identifier ?? "")")
							.font(.footnote)
							.foregroundStyle(.secondary)
							.lineLimit(1)
						Text(_details(entry))
							.font(.caption)
							.foregroundStyle(.secondary)
						if let error = entry.error {
							Text(error).font(.caption).foregroundStyle(.red)
						}
					}
					.swipeActions {
						if SigningHistory.sourceApp(for: entry) != nil {
							Button(.localized("Redo"), systemImage: "arrow.clockwise") { _redo(entry) }
								.tint(.blue)
						}
					}
					.contextMenu {
						if SigningHistory.sourceApp(for: entry) != nil {
							Button(.localized("Redo"), systemImage: "arrow.clockwise") { _redo(entry) }
						}
					}
				}
			} footer: {
				if !_entries.isEmpty {
					Text(.localized("Swipe an entry to sign it again with the same options and certificate (the original must still be in your library)."))
				}
			}

			if !_entries.isEmpty {
				Section {
					Button(.localized("Clear History"), role: .destructive) {
						SigningHistory.clear()
						_entries = []
					}
				}
			}
		}
		.disabled(_isRedoing)
		.overlay {
			if _isRedoing {
				ProgressView()
					.padding(24)
					.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
			}
		}
	}

	private func _details(_ entry: SigningHistoryEntry) -> String {
		var parts: [String] = []
		if let cert = entry.certificateName { parts.append(cert) }
		if let preset = entry.presetName { parts.append(String(format: .localized("preset %@"), preset)) }
		if !entry.options.injectionFiles.isEmpty { parts.append(String(format: .localized("%lld tweaks"), entry.options.injectionFiles.count)) }
		return parts.joined(separator: " • ")
	}

	private func _redo(_ entry: SigningHistoryEntry) {
		guard let app = SigningHistory.sourceApp(for: entry) else { return }
		let certificate = entry.certificateUUID.flatMap { Storage.shared.certificate(withUUID: $0) }
		let needsCertificate = !entry.options.doAdhocSigning && !entry.options.onlyModify
		guard !needsCertificate || certificate != nil else {
			_message = .localized("That certificate is gone, sign it again from the library.")
			return
		}

		_isRedoing = true
		_message = nil
		SigningHistory.pendingPresetName = entry.presetName
		FR.signPackageFile(app, using: entry.options, icon: nil, certificate: certificate) { error in
			_isRedoing = false
			_entries = SigningHistory.all()
			_message = error?.localizedDescription ?? String(format: .localized("%@ signed again"), entry.name)
		}
	}
}
