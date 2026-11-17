//
//  UpdatesView.swift
//  Ksign
//
//  apps in your library that have a newer version in one of your sources (matched by bundle identifier)
//

import SwiftUI
import CoreData
import AltSourceKit
import NimbleViews

struct UpdatesView: View {
	@ObservedObject private var _viewModel = SourcesViewModel.shared
	@ObservedObject private var _downloads = DownloadManager.shared
	@AppStorage(UpdateManager.autoSignKey) private var _autoSign = true

	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)],
		animation: .snappy
	) private var _sources: FetchedResults<AltSource>

	// only here so the list is recomputed when the library changes
	@FetchRequest(entity: Imported.entity(), sortDescriptors: []) private var _imported: FetchedResults<Imported>
	@FetchRequest(entity: Signed.entity(), sortDescriptors: []) private var _signed: FetchedResults<Signed>

	private var _outdated: [OutdatedApp] {
		_ = _imported.count + _signed.count
		return UpdateManager.outdated(in: _sources.compactMap { _viewModel.sources[$0] })
	}

	var body: some View {
		let list = _outdated

		List {
			Section {
				Toggle(isOn: $_autoSign) {
					Label(.localized("Sign updates automatically"), systemImage: "signature")
				}
			} footer: {
				Text(.localized("Apps you signed before are signed again with the same options and certificate as soon as the update is downloaded."))
			}

			if list.isEmpty {
				Section {
					Label(
						_viewModel.isFetching ? String.localized("Checking sources...") : String.localized("Everything is up to date"),
						systemImage: _viewModel.isFetching ? "arrow.triangle.2.circlepath" : "checkmark.seal"
					)
					.foregroundStyle(.secondary)
				}
			} else {
				Section {
					Button {
						UpdateManager.shared.updateAll(list)
					} label: {
						Label(String(format: .localized("Update All (%lld)"), list.count), systemImage: "arrow.down.circle")
					}
				}

				Section(.localized("Updates")) {
					ForEach(list) { item in
						_row(item)
					}
				}
			}
		}
		.navigationTitle(.localized("Updates"))
		.refreshable {
			await _viewModel.fetchSources(_sources, refresh: true)
		}
		.task {
			if _viewModel.sources.isEmpty {
				await _viewModel.fetchSources(_sources)
			}
		}
	}

	@ViewBuilder
	private func _row(_ item: OutdatedApp) -> some View {
		HStack {
			FRIconCellView(
				title: item.app.currentName,
				subtitle: "\(item.localVersion) → \(item.newVersion)  •  \(item.id)",
				iconUrl: item.app.iconURL
			)

			if let download = _downloads.getDownload(by: item.app.currentUniqueId) {
				ProgressView(value: download.overallProgress)
					.progressViewStyle(.circular)
			} else {
				Button {
					UpdateManager.shared.start(item.app)
				} label: {
					Text(.localized("Update"))
						.font(.headline.bold())
						.padding(.horizontal, 18)
						.padding(.vertical, 6)
						.background(Color(uiColor: .quaternarySystemFill))
						.clipShape(Capsule())
				}
				.buttonStyle(.borderless)
			}
		}
	}
}

// MARK: - Toolbar button with the number of pending updates
struct UpdatesLinkButton: View {
	@ObservedObject private var _viewModel = SourcesViewModel.shared

	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)]
	) private var _sources: FetchedResults<AltSource>
	@FetchRequest(entity: Imported.entity(), sortDescriptors: []) private var _imported: FetchedResults<Imported>
	@FetchRequest(entity: Signed.entity(), sortDescriptors: []) private var _signed: FetchedResults<Signed>

	private var _count: Int {
		_ = _imported.count + _signed.count
		return UpdateManager.outdated(in: _sources.compactMap { _viewModel.sources[$0] }).count
	}

	var body: some View {
		let count = _count
		NavigationLink {
			UpdatesView()
		} label: {
			Image(systemName: "arrow.triangle.2.circlepath.circle")
				.overlay(alignment: .topTrailing) {
					if count > 0 {
						Text("\(count)")
							.font(.system(size: 10, weight: .bold))
							.foregroundStyle(.white)
							.padding(.horizontal, 4)
							.background(Color.red, in: Capsule())
							.offset(x: 8, y: -6)
					}
				}
		}
	}
}
