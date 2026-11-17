//
//  HomeView.swift
//  Ksign
//
//  landing tab: hello, Quick Sign & Install and importing an ipa into the library
//

import SwiftUI
import CoreData
import NimbleViews

struct HomeView: View {
	@ObservedObject private var _downloads = DownloadManager.shared
	@ObservedObject private var _presets = SigningPresetStore.shared
	@ObservedObject private var _quickSign = QuickSign.shared

	@State private var _isImporting = false
	@State private var _appToSign: AnyApp?

	@FetchRequest(
		entity: CertificatePair.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.expiration, ascending: true)]
	) private var _certificates: FetchedResults<CertificatePair>

	/// the certificate that ends first (only the ones still valid)
	private var _soonestCertificate: CertificatePair? {
		_certificates.first { $0.revoked != true && ($0.expiration ?? .distantPast) > Date() }
	}

	@FetchRequest(
		entity: Imported.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \Imported.date, ascending: false)],
		animation: .snappy
	) private var _imported: FetchedResults<Imported>

	private var _greeting: String {
		switch Calendar.current.component(.hour, from: Date()) {
		case 5..<12: return .localized("Good morning")
		case 12..<18: return .localized("Good afternoon")
		default: return .localized("Good evening")
		}
	}

	var body: some View {
		NavigationStack {
			List {
				Section {
					VStack(alignment: .leading, spacing: 6) {
						Text(.localized("Hello 👋"))
							.font(.largeTitle.bold())
						Text(_greeting)
							.font(.title3)
							.foregroundStyle(.secondary)
					}
					.padding(.vertical, 8)
				}

				if let cert = _soonestCertificate, let expiration = cert.expiration {
					let days = Calendar.current.dateComponents([.day], from: Date(), to: expiration).day ?? 0
					Section {
						NavigationLink {
							BulkResignView()
						} label: {
							HStack {
								Image(systemName: days <= 3 ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
									.foregroundStyle(days <= 3 ? .red : (days <= 14 ? .orange : .green))
								VStack(alignment: .leading, spacing: 2) {
									Text(cert.nickname ?? .localized("Unknown"))
									Text(String(format: .localized("%lld days left"), days))
										.font(.footnote)
										.foregroundStyle(.secondary)
								}
							}
						}
					} header: {
						Text(.localized("Certificate"))
					} footer: {
						Text(.localized("Tap to sign your apps again with another certificate."))
					}
				}

				Section(.localized("Actions")) {
					Button {
						_isImporting = true
					} label: {
						Label(.localized("Import IPA to Library"), systemImage: "square.and.arrow.down")
					}

				}

				Section {
					if _presets.presets.isEmpty {
						NavigationLink {
							SigningPresetsView()
						} label: {
							Label(.localized("Create a signing preset to start"), systemImage: "bolt.badge.checkmark")
						}
					} else if _imported.isEmpty {
						Text(.localized("Import an IPA first, it shows up here."))
							.foregroundStyle(.secondary)
					} else {
						ForEach(_imported, id: \.uuid) { app in
							Button {
								_appToSign = AnyApp(base: app)
							} label: {
								HStack {
									FRAppIconView(app: app, size: 44)
									VStack(alignment: .leading, spacing: 2) {
										Text(app.name ?? .localized("Unknown"))
											.foregroundStyle(.primary)
										Text("\(app.version ?? "") • \(app.identifier ?? "")")
											.font(.footnote)
											.foregroundStyle(.secondary)
											.lineLimit(1)
									}
									Spacer()
									Image(systemName: "bolt.fill").foregroundStyle(.yellow)
								}
							}
						}
					}
				} header: {
					Text(.localized("Quick Sign & Install"))
				} footer: {
					if !_presets.presets.isEmpty {
						Text(.localized("Tap an app to sign it with a preset and install it right away."))
					}
				}
			}
			.navigationTitle(.localized("Home"))
			.confirmationDialog(
				_appToSign?.base.name ?? "",
				isPresented: Binding(get: { _appToSign != nil }, set: { if !$0 { _appToSign = nil } }),
				titleVisibility: .visible
			) {
				ForEach(_presets.ordered) { preset in
					Button(preset.name) {
						if let app = _appToSign { QuickSign.shared.run(app.base, preset: preset) }
					}
				}
			}
			.overlay {
				if let status = _quickSign.status {
					VStack(spacing: 12) {
						ProgressView()
						Text(status).font(.footnote)
					}
					.padding(24)
					.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
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
}
