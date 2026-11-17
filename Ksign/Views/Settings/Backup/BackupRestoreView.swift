//
//  BackupRestoreView.swift
//  Ksign
//

import SwiftUI
import UniformTypeIdentifiers
import NimbleViews

struct BackupRestoreView: View {
	@State private var _isRestoring = false
	@State private var _isPickingFile = false
	@State private var _message: String?

	var body: some View {
		NBList(.localized("Backup & Restore")) {
			Section {
				Button {
					_export()
				} label: {
					Label(.localized("Create Backup"), systemImage: "square.and.arrow.up")
				}

				Button {
					_isPickingFile = true
				} label: {
					Label(.localized("Restore Backup"), systemImage: "square.and.arrow.down")
				}
				.disabled(_isRestoring)
			} footer: {
				Text(.localized("The backup is a zip with your sources and certificates (including their passwords, as plain text). Keep it private. Restoring only adds what is missing, nothing is replaced."))
			}

			if _isRestoring {
				Section { ProgressView(.localized("Restoring...")) }
			}

			if let _message {
				Section { Text(_message).font(.footnote) }
			}
		}
		.sheet(isPresented: $_isPickingFile) {
			FileImporterRepresentableView(
				allowedContentTypes: [.zip],
				onDocumentsPicked: { urls in
					guard let url = urls.first else { return }
					_restore(url)
				}
			)
		}
	}

	private func _export() {
		do {
			let zip = try BackupManager.export()
			UIActivityViewController.show(activityItems: [zip])
		} catch {
			_message = error.localizedDescription
		}
	}

	private func _restore(_ url: URL) {
		_isRestoring = true
		_message = nil
		Task { @MainActor in
			defer { _isRestoring = false }
			do {
				let result = try await BackupManager.restore(from: url)
				_message = String(
					format: .localized("Restored %lld sources and %lld certificates (%lld already here)"),
					result.sources, result.certificates, result.skipped
				)
			} catch {
				_message = error.localizedDescription
			}
		}
	}
}
