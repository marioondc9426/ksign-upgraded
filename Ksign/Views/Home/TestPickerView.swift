//
//  TestPickerView.swift
//  Ksign
//
//  "Test tweaks in game": pick one of your downloaded apps (or import a new one with +),
//  then Ksign opens the signing screen and, after signing, the tweak test
//

import SwiftUI
import CoreData

struct TestPickerView: View {
	@Environment(\.dismiss) private var _dismiss
	@ObservedObject private var _downloads = DownloadManager.shared
	@State private var _isImporting = false

	@FetchRequest(
		entity: Imported.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \Imported.date, ascending: false)],
		animation: .snappy
	) private var _imported: FetchedResults<Imported>

	var body: some View {
		NavigationStack {
			List {
				if _imported.isEmpty {
					Section {
						Text(.localized("No downloaded apps yet. Tap + to import an IPA."))
							.foregroundStyle(.secondary)
					}
				}

				Section {
					ForEach(_imported, id: \.uuid) { app in
						Button {
							_pick(app)
						} label: {
							HStack {
								FRAppIconView(app: app, size: 44)
								VStack(alignment: .leading, spacing: 2) {
									Text(app.name ?? .localized("Unknown")).foregroundStyle(.primary)
									Text("\(app.version ?? "") • \(app.identifier ?? "")")
										.font(.footnote)
										.foregroundStyle(.secondary)
										.lineLimit(1)
								}
								Spacer()
								Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
							}
						}
					}
				} footer: {
					if !_imported.isEmpty {
						Text(.localized("Sign it (add your tweaks there), then Ksign checks it, installs it and helps you find out why it crashes."))
					}
				}
			}
			.navigationTitle(.localized("Pick an app"))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					Button(.localized("Cancel")) { _dismiss() }
				}
				ToolbarItem(placement: .topBarTrailing) {
					Button {
						_isImporting = true
					} label: {
						Image(systemName: "plus")
					}
				}
			}
			.sheet(isPresented: $_isImporting) {
				FileImporterRepresentableView(
					allowedContentTypes: [.ipa, .tipa],
					allowsMultipleSelection: true,
					onDocumentsPicked: { urls in
						for url in urls {
							let id = "FeatherManualDownload_\(UUID().uuidString)"
							let dl = _downloads.startArchive(from: url, id: id)
							_downloads.handlePachageFile(url: url, dl: dl) { error in
								if error != nil {
									UIAlertController.showAlertWithOk(title: "Error", message: .localized("Whoops!, something went wrong when extracting the file. \nMaybe try switching the extraction library in the settings?"))
								}
							}
						}
					}
				)
			}
		}
	}

	private func _pick(_ app: Imported) {
		_dismiss()
		Task { @MainActor in
			// let this sheet close before the signing screen opens
			try? await Task.sleep(nanoseconds: 450_000_000)
			AppPresenter.shared.sign(app, test: true)
		}
	}
}
