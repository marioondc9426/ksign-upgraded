//
//  BulkResignView.swift
//  Ksign
//
//  sign the apps in the Signed tab again with another certificate, one after another
//

import SwiftUI
import CoreData
import NimbleViews

struct BulkResignView: View {
	@FetchRequest(
		entity: CertificatePair.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.expiration, ascending: false)]
	) private var _certificates: FetchedResults<CertificatePair>

	@FetchRequest(
		entity: Signed.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \Signed.date, ascending: false)]
	) private var _signed: FetchedResults<Signed>

	@State private var _certUUID: String?
	@State private var _selected: Set<String> = []
	@State private var _removeOld = true
	@State private var _running = false
	@State private var _done = 0
	@State private var _failed: [String] = []
	@State private var _message: String?

	private var _cert: CertificatePair? {
		_certificates.first { $0.uuid == _certUUID }
	}

	private var _pendingOffer: CertificatePair? {
		guard let uuid = UserDefaults.standard.string(forKey: CertificateWatcher.pendingKey) else { return nil }
		return _certificates.first { $0.uuid == uuid }
	}

	var body: some View {
		NBList(.localized("Bulk Re-sign")) {
			if let offer = _pendingOffer {
				Section {
					Label(String(format: .localized("New certificate: %@"), offer.nickname ?? .localized("Unknown")), systemImage: "sparkles")
				}
			}

			Section(.localized("Certificate")) {
				Picker(.localized("Sign with"), selection: $_certUUID) {
					ForEach(_certificates.filter { $0.revoked != true }, id: \.uuid) { cert in
						Text("\(cert.nickname ?? .localized("Unknown")) • \(_expires(cert))").tag(cert.uuid as String?)
					}
				}
				Toggle(.localized("Remove the old copies"), isOn: $_removeOld)
			}

			Section {
				ForEach(_signed, id: \.uuid) { app in
					Button {
						_toggle(app)
					} label: {
						HStack {
							Image(systemName: _selected.contains(app.uuid ?? "") ? "checkmark.circle.fill" : "circle")
								.foregroundStyle(_selected.contains(app.uuid ?? "") ? Color.accentColor : .secondary)
							VStack(alignment: .leading, spacing: 2) {
								Text(app.name ?? .localized("Unknown")).foregroundStyle(.primary)
								Text("\(app.version ?? "") • \(app.certificate?.nickname ?? "-") • \(app.certificate.map { _expires($0) } ?? "-")")
									.font(.footnote)
									.foregroundStyle(.secondary)
									.lineLimit(1)
							}
						}
					}
				}
			} header: {
				HStack {
					Text(.localized("Signed Apps"))
					Spacer()
					Button(.localized("Older certificates")) { _selectOlder() }.font(.footnote)
					Button(.localized("All")) { _selected = Set(_signed.compactMap { $0.uuid }) }.font(.footnote)
				}
			}

			Section {
				Button {
					_start()
				} label: {
					if _running {
						HStack {
							ProgressView()
							Text(String(format: .localized("Signing %lld of %lld"), min(_done + 1, _selected.count), _selected.count))
						}
					} else {
						Label(String(format: .localized("Re-sign %lld apps"), _selected.count), systemImage: "signature")
					}
				}
				.disabled(_running || _selected.isEmpty || _cert == nil)

				if let _message { Text(_message).font(.footnote) }
				ForEach(_failed, id: \.self) { Text($0).font(.footnote).foregroundStyle(.red) }
			}
		}
		.onAppear {
			guard _certUUID == nil else { return }
			_certUUID = _pendingOffer?.uuid ?? _certificates.first { $0.revoked != true }?.uuid
			_selectOlder()
		}
		.onChange(of: _certUUID) { _ in _selectOlder() }
	}

	private func _expires(_ cert: CertificatePair) -> String {
		(cert.expiration ?? .distantPast).formatted(date: .abbreviated, time: .omitted)
	}

	private func _toggle(_ app: Signed) {
		guard let uuid = app.uuid else { return }
		if _selected.contains(uuid) { _selected.remove(uuid) } else { _selected.insert(uuid) }
	}

	private func _selectOlder() {
		guard let cert = _cert else { return }
		_selected = Set(CertificateWatcher.appsWithOlderCertificate(than: cert).compactMap { $0.uuid })
	}

	private func _options(for app: Signed) -> Options {
		var options: Options
		if let id = app.identifier, let profile = SignProfiles.profile(for: id) {
			options = profile.options
		} else if let preset = SigningPresetStore.shared.ordered.first {
			options = SigningPresetStore.shared.resolve(preset, for: app).options
		} else {
			options = OptionsManager.shared.options
		}
		// the app already has its final name, identifier and version
		options.appName = nil
		options.appIdentifier = nil
		options.appVersion = nil
		options.removeApp = false
		AppSyncSupport.apply(&options)
		return options
	}

	private func _start() {
		guard let cert = _cert else { return }
		let apps = _signed.filter { _selected.contains($0.uuid ?? "") }
		_running = true
		_done = 0
		_failed = []
		_message = nil

		Task { @MainActor in
			var ok = 0
			for app in apps {
				let name = app.name ?? .localized("Unknown")
				let options = _options(for: app)
				let error: Error? = await withCheckedContinuation { continuation in
					FR.signPackageFile(app, using: options, icon: nil, certificate: cert) { error in
						continuation.resume(returning: error)
					}
				}
				if let error {
					_failed.append("\(name): \(error.localizedDescription)")
				} else {
					ok += 1
					if _removeOld { Storage.shared.deleteApp(for: app) }
				}
				_done += 1
			}
			_running = false
			_selected = []
			UserDefaults.standard.removeObject(forKey: CertificateWatcher.pendingKey)
			_message = String(format: .localized("Signed again: %lld of %lld"), ok, apps.count)
		}
	}
}
