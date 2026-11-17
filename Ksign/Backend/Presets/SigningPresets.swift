//
//  SigningPresets.swift
//  Ksign
//
//  reusable signing presets: a full set of options + a certificate, with optional rules
//  that change things for specific apps (matched by bundle identifier or name)
//

import Foundation
import CoreData
import UIKit
import SwiftUI

/// changes applied on top of a preset when the app matches `pattern`
struct PresetRule: Codable, Identifiable, Equatable {
	var id = UUID().uuidString
	/// bundle identifier or app name, `*` and `?` work as wildcards (`com.google.*`)
	var pattern: String = ""
	var appName: String?
	var appIdentifier: String?
	/// uuid of the certificate to use for this app instead of the preset one
	var certificateUUID: String?
	/// sign this app without the tweaks of the preset
	var removeTweaks: Bool = false

	func matches(_ app: AppInfoPresentable) -> Bool {
		let pattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !pattern.isEmpty else { return false }
		let predicate = NSPredicate(format: "SELF LIKE[c] %@", pattern)
		return [app.identifier, app.name].compactMap { $0 }.contains { predicate.evaluate(with: $0) }
	}
}

struct SigningPreset: Codable, Identifiable, Equatable {
	var id = UUID().uuidString
	var name: String
	var options: Options
	/// uuid of the CertificatePair (nil = the certificate selected in the app)
	var certificateUUID: String?
	var rules: [PresetRule] = []
}

final class SigningPresetStore: ObservableObject {
	static let shared = SigningPresetStore()

	private let _presetsKey = "ksign.signingPresets"
	private let _defaultKey = "ksign.defaultSigningPreset"

	@Published var presets: [SigningPreset] = [] {
		didSet { _save() }
	}

	/// the preset used by "Quick Sign & Install"
	@Published var defaultID: String? {
		didSet { UserDefaults.standard.set(defaultID, forKey: _defaultKey) }
	}

	private init() {
		if
			let data = UserDefaults.standard.data(forKey: _presetsKey),
			let decoded = try? JSONDecoder().decode([SigningPreset].self, from: data)
		{
			presets = decoded
		}
		defaultID = UserDefaults.standard.string(forKey: _defaultKey)
	}

	private func _save() {
		if let data = try? JSONEncoder().encode(presets) {
			UserDefaults.standard.set(data, forKey: _presetsKey)
		}
	}

	/// presets with the default one first
	var ordered: [SigningPreset] {
		presets.sorted { ($0.id == defaultID ? 0 : 1) < ($1.id == defaultID ? 0 : 1) }
	}

	@discardableResult
	func add(name: String, options: Options, certificateUUID: String?) -> SigningPreset {
		let preset = SigningPreset(name: name, options: options, certificateUUID: certificateUUID)
		presets.append(preset)
		if defaultID == nil { defaultID = preset.id }
		return preset
	}

	func remove(_ id: String) {
		presets.removeAll { $0.id == id }
		if defaultID == id { defaultID = presets.first?.id }
	}

	func binding(for id: String) -> Binding<SigningPreset>? {
		guard presets.contains(where: { $0.id == id }) else { return nil }
		return Binding(
			get: { self.presets.first(where: { $0.id == id }) ?? SigningPreset(name: "", options: Options.defaultOptions) },
			set: { new in
				if let index = self.presets.firstIndex(where: { $0.id == id }) { self.presets[index] = new }
			}
		)
	}

	// MARK: Resolving
	/// options and certificate to use when `preset` is applied to `app` (rules included)
	func resolve(_ preset: SigningPreset, for app: AppInfoPresentable) -> (options: Options, certificate: CertificatePair?) {
		var options = preset.options
		let rule = preset.rules.first { $0.matches(app) }

		if rule?.removeTweaks == true { options.injectionFiles = [] }

		let certificateUUID = rule?.certificateUUID ?? preset.certificateUUID
		let certificate = certificateUUID.flatMap { Storage.shared.certificate(withUUID: $0) }
			?? Storage.shared.selectedCertificate()

		if AppSyncSupport.shouldSkipSigning { options.onlyModify = true }

		// same things the signing screen does when it opens
		options.appName = nil
		options.appIdentifier = nil
		options.appVersion = nil

		if
			options.ppqProtection,
			let identifier = app.identifier,
			let certificate, certificate.ppQCheck
		{
			options.appIdentifier = "\(identifier).\(options.ppqString)"
		}
		if let identifier = app.identifier, let mapped = options.identifiers[identifier] {
			options.appIdentifier = mapped
		}

		if options.prefix != nil || options.suffix != nil || options.displayNames[app.name ?? ""] != nil {
			var name = app.name ?? ""
			if let mapped = options.displayNames[name] { name = mapped }
			if let prefix = options.prefix { name = prefix + name }
			if let suffix = options.suffix { name += suffix }
			options.appName = name
		}

		if let rule {
			if let name = rule.appName, !name.isEmpty { options.appName = name }
			if let identifier = rule.appIdentifier, !identifier.isEmpty { options.appIdentifier = identifier }
		}

		return (options, certificate)
	}
}

extension Storage {
	/// the certificate picked in the signing screen (stored as an index of the list sorted by date)
	func selectedCertificate() -> CertificatePair? {
		let request = NSFetchRequest<CertificatePair>(entityName: "CertificatePair")
		request.sortDescriptors = [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)]
		guard let all = try? context.fetch(request), !all.isEmpty else { return nil }
		let index = UserDefaults.standard.integer(forKey: "feather.selectedCert")
		return all.indices.contains(index) ? all[index] : all.first
	}
}

// MARK: - Quick Sign & Install
@MainActor
final class QuickSign: ObservableObject {
	static let shared = QuickSign()

	/// shown over the library while something is being signed
	@Published var status: String?

	func run(_ app: AppInfoPresentable, preset: SigningPreset, install: Bool = true) {
		guard status == nil else { return }

		let resolved = SigningPresetStore.shared.resolve(preset, for: app)
		let options = resolved.options

		guard resolved.certificate != nil || options.doAdhocSigning || options.onlyModify else {
			UIAlertController.showAlertWithOk(
				title: .localized("No Certificate"),
				message: .localized("Please go to settings and import a valid certificate"),
				isCancel: true
			)
			return
		}

		UIImpactFeedbackGenerator(style: .light).impactOccurred()
		status = String(format: .localized("Signing %@..."), app.name ?? .localized("Unknown"))

		FR.signPackageFile(app, using: options, icon: nil, certificate: resolved.certificate) { error in
			Task { @MainActor in
				self.status = nil
				if let error {
					LogsManager.shared.showErrorAlert(
						title: .localized("Signing"),
						message: error.localizedDescription,
						onDismiss: {}
					)
					return
				}

				if options.removeApp && !app.isSigned {
					Storage.shared.deleteApp(for: app)
				}
				if install {
					// the library opens the install sheet for the newest signed app
					try? await Task.sleep(nanoseconds: 400_000_000)
					NotificationCenter.default.post(name: NSNotification.Name("feather.installApp"), object: nil)
				}
			}
		}
	}

	/// the preset used by the one-tap action (default one, or the only one)
	func run(_ app: AppInfoPresentable) {
		let store = SigningPresetStore.shared
		guard let preset = store.ordered.first else { return }
		run(app, preset: preset)
	}
}
