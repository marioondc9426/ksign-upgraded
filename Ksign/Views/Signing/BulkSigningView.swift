//
//  BulkSigningView.swift
//  Ksign
//
//  Created by Nagata Asami on 11/9/25.
//

import SwiftUI
import NimbleViews
import PhotosUI

struct AppSignConfig: Identifiable {
    var id: String? { app.uuid }
    var app: AppInfoPresentable
    var options: Options
    var icon: UIImage?
}

struct BulkSigningView: View {
	@FetchRequest(
		entity: CertificatePair.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)],
		animation: .snappy
	) private var certificates: FetchedResults<CertificatePair>
	
	private func _selectedCert() -> CertificatePair? {
		guard certificates.indices.contains(_temporaryCertificate) else { return nil }
		return certificates[_temporaryCertificate]
	}
	
	@StateObject private var _optionsManager = OptionsManager.shared
	@State private var _configs: [AppSignConfig]
	@State private var _temporaryCertificate: Int
	@State private var _isAltPickerPresenting = false
	@State private var _isFilePickerPresenting = false
	@State private var _isImagePickerPresenting = false
	@State private var _isSigning = false
	/// tweaks added here go into every app (each app can still have its own under Modify > Tweaks)
	@State private var _sharedTweaks: Options
	@State private var _multiCerts: Set<Int> = []   // Multi Sign: extra certificates (empty = just the one chosen above)
	@State private var _signDone = 0
	@State private var _signTotal = 0
	@State private var _selectedPhoto: PhotosPickerItem? = nil
	@State private var _editingConfigId: String?
	
	@Environment(\.dismiss) private var dismiss
	var apps: [AppInfoPresentable]

	init(apps: [AppInfoPresentable]) {
		self.apps = apps
		let storedCert = UserDefaults.standard.integer(forKey: "feather.selectedCert")
		__temporaryCertificate = State(initialValue: storedCert)
		
		let defaultOptions = OptionsManager.shared.options
		__configs = State(initialValue: apps.map { AppSignConfig(app: $0, options: defaultOptions, icon: nil) })
		var shared = defaultOptions
		shared.injectionFiles = []   // only what is added here is new, the defaults are already in every app
		__sharedTweaks = State(initialValue: shared)
	}

	@ObservedObject private var _presets = SigningPresetStore.shared

	@ViewBuilder
	private func _presetSection() -> some View {
		if !_presets.presets.isEmpty {
			Section {
				Menu {
					ForEach(_presets.ordered) { preset in
						Button(preset.name) { _applyPreset(preset) }
					}
				} label: {
					LabeledContent(.localized("Apply Preset to All")) {
						Image(systemName: "chevron.up.chevron.down").font(.footnote).foregroundStyle(.secondary)
					}
				}
			} footer: {
				Text(.localized("Sets the options of every app below from the preset, including its rules for specific apps. The certificate chosen below is used for all of them."))
			}
		}
	}

	private func _applyPreset(_ preset: SigningPreset) {
		for index in _configs.indices {
			_configs[index].options = _presets.resolve(preset, for: _configs[index].app).options
		}
		if
			let uuid = preset.certificateUUID,
			let cert = Storage.shared.certificate(withUUID: uuid),
			let index = certificates.firstIndex(of: cert)
		{
			_temporaryCertificate = index
		}
	}

	var body: some View {
		NBNavigationView(.localized("Bulk Signing"), displayMode: .inline) {
			Form {
				_presetSection()
                _cert()
				
				ForEach($_configs) { $config in
					Section {
						_customizationOptions(for: $config)
						_customizationProperties(for: $config)
					}
				}
			}
			.safeAreaInset(edge: .bottom) {
				Button {
					_start()
				} label: {
					NBSheetButton(title: .localized("Start Signing"))
				}
			}
			.toolbar {
				NBToolbarButton(role: .dismiss)
				
				NBToolbarButton(
					.localized("Reset"),
					style: .text,
					placement: .topBarTrailing
				) {
					let defaultOptions = OptionsManager.shared.options
					for i in _configs.indices {
						_configs[i].options = defaultOptions
						_configs[i].icon = nil
					}
				}
			}
			.sheet(isPresented: $_isAltPickerPresenting) {
				if let id = _editingConfigId, let index = _configs.firstIndex(where: { $0.id == id }) {
					let appBase = _configs[index].app
					let iconBinding = Binding<UIImage?>(
						get: { _configs[index].icon },
						set: { _configs[index].icon = $0 }
					)
					SigningAlternativeIconView(app: appBase, appIcon: iconBinding, isModifing: .constant(true))
				}
			}
			.sheet(isPresented: $_isFilePickerPresenting) {
				FileImporterRepresentableView(
					allowedContentTypes:  [.image],
					onDocumentsPicked: { urls in
						guard let selectedFileURL = urls.first else { return }
						guard let id = _editingConfigId, let index = _configs.firstIndex(where: { $0.id == id }) else { return }
						_configs[index].icon = UIImage.fromFile(selectedFileURL)?.resizeToSquare()
					}
				)
			}
			.photosPicker(isPresented: $_isImagePickerPresenting, selection: $_selectedPhoto)
			.onChange(of: _selectedPhoto) { newValue in
				guard let newValue else { return }
				
				Task { @MainActor in
					if let data = try? await newValue.loadTransferable(type: Data.self),
					   let image = UIImage(data: data)?.resizeToSquare() {
						if let id = _editingConfigId, let index = _configs.firstIndex(where: { $0.id == id }) {
							_configs[index].icon = image
						}
					}
				}
			}
			.disabled(_isSigning)
			.overlay {
				if _isSigning {
					VStack(spacing: 12) {
						ProgressView(value: Double(_signDone), total: Double(max(_signTotal, 1)))
						Text(String(format: .localized("Signing %lld of %lld"), min(_signDone + 1, _signTotal), _signTotal))
							.font(.footnote)
					}
					.padding(20)
					.frame(maxWidth: 260)
					.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
				}
			}
			.animation(.smooth, value: _isSigning)
		}
	}
}

extension BulkSigningView {
	@ViewBuilder
	private func _customizationOptions(for config: Binding<AppSignConfig>) -> some View {
			Menu {
				Button(.localized("Select Alternative Icon")) {
					_editingConfigId = config.wrappedValue.id
					_isAltPickerPresenting = true 
				}
				Button(.localized("Choose from Files")) {
					_editingConfigId = config.wrappedValue.id
					_isFilePickerPresenting = true 
				}
				Button(.localized("Choose from Photos")) {
					_editingConfigId = config.wrappedValue.id
					_isImagePickerPresenting = true 
				}
			} label: {
				if let customIcon = config.icon.wrappedValue {
					Image(uiImage: customIcon)
						.resizable()
						.frame(width: 55, height: 55)
						.cornerRadius(12)
				} else {
					FRAppIconView(app: config.app.wrappedValue, size: 55)
				}
			}
			_infoCell(.localized("Name"), desc: config.options.appName.wrappedValue ?? config.app.wrappedValue.name) {
				SigningPropertiesView(
					title: .localized("Name"),
					initialValue: config.options.appName.wrappedValue ?? (config.app.wrappedValue.name ?? ""),
					bindingValue: config.options.appName
				)
			}
			_infoCell(.localized("Identifier"), desc: config.options.appIdentifier.wrappedValue ?? config.app.wrappedValue.identifier) {
				SigningPropertiesView(
					title: .localized("Identifier"),
					initialValue: config.options.appIdentifier.wrappedValue ?? (config.app.wrappedValue.identifier ?? ""),
					bindingValue: config.options.appIdentifier
				)
			}
			_infoCell(.localized("Version"), desc: config.options.appVersion.wrappedValue ?? config.app.wrappedValue.version) {
				SigningPropertiesView(
					title: .localized("Version"),
					initialValue: config.options.appVersion.wrappedValue ?? (config.app.wrappedValue.version ?? ""),
					bindingValue: config.options.appVersion
				)
			}
	}
	

	@ViewBuilder
	private func _cert() -> some View {
		NBSection(.localized("Signing")) {
			if let cert = _selectedCert() {
				NavigationLink {
					CertificatesView(selectedCert: $_temporaryCertificate)
				} label: {
					CertificatesCellView(
						cert: cert
					)
				}
			}
			
			NavigationLink {
				SigningTweaksView(options: $_sharedTweaks)
			} label: {
				LabeledContent(String.localized("Tweaks (All Apps)")) {
					Text(_sharedTweaks.injectionFiles.isEmpty ? String.localized("None") : "\(_sharedTweaks.injectionFiles.count)")
				}
			}
			
			NavigationLink {
				MultiCertificatePickerView(selection: $_multiCerts)
			} label: {
				LabeledContent(String.localized("Multi Sign")) {
					Text(_multiSignLabel)
				}
			}
		}
	}
	
	@ViewBuilder
	private func _customizationProperties(for config: Binding<AppSignConfig>) -> some View {
			DisclosureGroup(.localized("Modify")) {
				NavigationLink(.localized("Existing Dylibs")) {
					SigningDylibView(
						app: config.app.wrappedValue,
						options: config.options.optional()
					)
				}
				
				NavigationLink(String.localized("Frameworks & PlugIns")) {
					SigningFrameworksView(
						app: config.app.wrappedValue,
						options: config.options.optional()
					)
				}
				#if NIGHTLY || DEBUG
				NavigationLink(String.localized("Entitlements")) {
					SigningEntitlementsView(
						bindingValue: config.options.appEntitlementsFile
					)
				}
				#endif
				NavigationLink(String.localized("Tweaks")) {
					SigningTweaksView(
						options: config.options
					)
				}
			}
			
			NavigationLink(String.localized("Properties")) {
				Form { SigningOptionsView(
					options: config.options,
					temporaryOptions: _optionsManager.options
				)}
			.navigationTitle(.localized("Properties"))
		}
	}

	@ViewBuilder
	private func _infoCell<V: View>(_ title: String, desc: String?, @ViewBuilder destination: () -> V) -> some View {
		NavigationLink {
			destination()
		} label: {
			LabeledContent(title) {
				Text(desc ?? .localized("Unknown"))
			}
		}
	}

	private var _multiSignLabel: String {
		if _multiCerts.isEmpty { return .localized("Off") }
		return String(format: .localized("%lld certificates"), _multiCerts.count)
	}
	
	/// adds the tweaks chosen for all apps on top of the app's own options
	private func _withSharedTweaks(_ options: Options) -> Options {
		guard !_sharedTweaks.injectionFiles.isEmpty else { return options }
		var merged = options
		for tweak in _sharedTweaks.injectionFiles where !merged.injectionFiles.contains(tweak) {
			merged.injectionFiles.append(tweak)
		}
		merged.injectPath = _sharedTweaks.injectPath
		merged.injectFolder = _sharedTweaks.injectFolder
		merged.injectIntoExtensions = _sharedTweaks.injectIntoExtensions
		return merged
	}
	
	private struct SignJob {
		let app: AppInfoPresentable
		let options: Options
		let icon: UIImage?
		let cert: CertificatePair?
		let certName: String
	}
	
	/// every app x every selected certificate (or just the one chosen above when Multi Sign is off)
	private func _jobs() -> [SignJob] {
		let chosen = _multiCerts.sorted().compactMap { certificates.indices.contains($0) ? certificates[$0] : nil }
		var jobs: [SignJob] = []
		
		for var config in _configs {
			config.options = _withSharedTweaks(config.options)
			if config.options.doAdhocSigning || config.options.onlyModify || chosen.isEmpty {
				let cert = _selectedCert()
				jobs.append(SignJob(app: config.app, options: config.options, icon: config.icon, cert: cert, certName: cert?.nickname ?? "-"))
			} else {
				for cert in chosen {
					jobs.append(SignJob(app: config.app, options: config.options, icon: config.icon, cert: cert, certName: cert.nickname ?? .localized("Unknown")))
				}
			}
		}
		return jobs
	}

	private func _start() {
		let canSign = !_multiCerts.isEmpty || _selectedCert() != nil || _configs.allSatisfy { $0.options.doAdhocSigning || $0.options.onlyModify }
		guard canSign else {
			UIAlertController.showAlertWithOk(
				title: .localized("No Certificate"),
				message: .localized("Please go to settings and import a valid certificate"),
				isCancel: true
			)
			return
		}

		let jobs = _jobs()
		guard !jobs.isEmpty else { return }
		
		let generator = UIImpactFeedbackGenerator(style: .light)
		generator.impactOccurred()
		_signDone = 0
		_signTotal = jobs.count
		_isSigning = true
		
		// one at a time: signing copies and rewrites whole apps, running them all together spikes memory
		// and two jobs for the same app would fight over the same files
		Task { @MainActor in
			var failures: [String] = []
			
			for (index, job) in jobs.enumerated() {
				_signDone = index
				
				let error: Error? = await withCheckedContinuation { continuation in
					FR.signPackageFile(
						job.app,
						using: job.options,
						icon: job.icon,
						certificate: job.cert
					) { error in
						continuation.resume(returning: error)
					}
				}
				
				if let error {
					failures.append("\(job.app.name ?? "?") (\(job.certName)): \(error.localizedDescription)")
				}
			}
			
			_signDone = jobs.count
			
			let finish = {
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
					NotificationCenter.default.post(name: NSNotification.Name("ksign.bulkSigningFinished"), object: nil)
				}
				dismiss()
			}
			
			if failures.isEmpty {
				finish()
			} else {
				LogsManager.shared.showErrorAlert(
					title: .localized("Signing"),
					message: failures.joined(separator: "\n"),
					onDismiss: finish
				)
			}
		}
	}
}
