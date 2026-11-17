//
//  SigningPresetsView.swift
//  Ksign
//
//  create and edit signing presets, and the per-app rules inside them
//

import SwiftUI
import NimbleViews

// MARK: - List
struct SigningPresetsView: View {
	@ObservedObject private var _store = SigningPresetStore.shared
	@State private var _isNaming = false
	@State private var _newName = ""

	@FetchRequest(
		entity: CertificatePair.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)]
	) private var _certificates: FetchedResults<CertificatePair>

	var body: some View {
		NBList(.localized("Signing Presets")) {
			Section {
				if _store.presets.isEmpty {
					Text(.localized("No presets yet. Create one here or use Save as Preset in the signing screen."))
						.foregroundStyle(.secondary)
				}

				ForEach(_store.ordered) { preset in
					NavigationLink {
						SigningPresetEditView(presetID: preset.id)
					} label: {
						HStack {
							VStack(alignment: .leading, spacing: 2) {
								Text(preset.name)
								if let desc = preset.desc, !desc.isEmpty {
									Text(desc)
										.font(.footnote)
										.foregroundStyle(.secondary)
										.lineLimit(2)
								}
								Text(_subtitle(preset))
									.font(.caption)
									.foregroundStyle(.secondary)
							}
							Spacer()
							if preset.id == _store.defaultID {
								Image(systemName: "bolt.fill").foregroundStyle(.yellow)
							}
						}
					}
					.swipeActions {
						Button(.localized("Delete"), systemImage: "trash", role: .destructive) {
							_store.remove(preset.id)
						}
						Button(.localized("Default"), systemImage: "bolt") {
							_store.defaultID = preset.id
						}
						.tint(.orange)
					}
				}
			} footer: {
				Text(.localized("The default preset (bolt) is used by Quick Sign & Install in the library. Swipe a preset to make it the default."))
			}
		}
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Button {
					_newName = ""
					_isNaming = true
				} label: {
					Image(systemName: "plus")
				}
			}
		}
		.sheet(isPresented: $_isNaming) {
			NewPresetSheet { name, desc, options in
				guard !name.isEmpty else { return }
				_store.add(name: name, desc: desc, options: options, certificateUUID: Storage.shared.selectedCertificate()?.uuid)
			}
		}
	}

	private func _subtitle(_ preset: SigningPreset) -> String {
		var parts: [String] = []
		if let uuid = preset.certificateUUID, let cert = Storage.shared.certificate(withUUID: uuid) {
			parts.append(cert.nickname ?? .localized("Unknown"))
		}
		if !preset.rules.isEmpty {
			parts.append(String(format: .localized("%lld rules"), preset.rules.count))
		}
		return parts.isEmpty ? .localized("Selected certificate") : parts.joined(separator: " • ")
	}
}

// MARK: - Edit
struct SigningPresetEditView: View {
	let presetID: String

	@ObservedObject private var _store = SigningPresetStore.shared
	@Environment(\.dismiss) private var _dismiss

	@FetchRequest(
		entity: CertificatePair.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)]
	) private var _certificates: FetchedResults<CertificatePair>

	var body: some View {
		if let preset = SigningPresetStore.shared.binding(for: presetID) {
			Form {
				Section(.localized("Preset")) {
					TextField(.localized("Name"), text: preset.name)
					TextField(.localized("Description"), text: Binding(
						get: { preset.wrappedValue.desc ?? "" },
						set: { preset.wrappedValue.desc = $0.isEmpty ? nil : $0 }
					), axis: .vertical)

					Picker(.localized("Certificate"), selection: preset.certificateUUID) {
						Text(.localized("Selected certificate")).tag(String?.none)
						ForEach(_certificates, id: \.uuid) { cert in
							Text(cert.nickname ?? .localized("Unknown")).tag(cert.uuid as String?)
						}
					}

					Toggle(.localized("Use for Quick Sign"), isOn: Binding(
						get: { _store.defaultID == presetID },
						set: { if $0 { _store.defaultID = presetID } }
					))
				}

				Section {
					NavigationLink(.localized("Properties")) {
						Form {
							SigningOptionsView(options: preset.options, temporaryOptions: OptionsManager.shared.options)
						}
						.navigationTitle(.localized("Properties"))
					}
					NavigationLink(.localized("Tweaks")) {
						SigningTweaksView(options: preset.options)
					}
					Button(.localized("Replace with current options")) {
						preset.wrappedValue.options = OptionsManager.shared.options
					}
				} header: {
					Text(.localized("Options"))
				} footer: {
					Text(.localized("Name, identifier and version are set per app, so they are not part of a preset. Use rules for that."))
				}

				Section {
					ForEach(preset.rules) { $rule in
						NavigationLink {
							PresetRuleEditView(rule: $rule, certificates: Array(_certificates))
						} label: {
							VStack(alignment: .leading, spacing: 2) {
								Text(rule.pattern.isEmpty ? String.localized("New rule") : rule.pattern)
								Text(_summary(rule))
									.font(.footnote)
									.foregroundStyle(.secondary)
							}
						}
					}
					.onDelete { offsets in
						preset.wrappedValue.rules.remove(atOffsets: offsets)
					}

					Button {
						preset.wrappedValue.rules.append(PresetRule())
					} label: {
						Label(.localized("Add Rule"), systemImage: "plus")
					}
				} header: {
					Text(.localized("Rules for specific apps"))
				} footer: {
					Text(.localized("The first rule that matches an app (by bundle identifier or name) changes the preset for that app only. Use * as a wildcard, like com.google.*"))
				}

				Section {
					Button(.localized("Delete Preset"), role: .destructive) {
						_store.remove(presetID)
						_dismiss()
					}
				}
			}
			.navigationTitle(preset.wrappedValue.name)
			.navigationBarTitleDisplayMode(.inline)
		}
	}

	private func _summary(_ rule: PresetRule) -> String {
		var parts: [String] = []
		if let name = rule.appName, !name.isEmpty { parts.append(String(format: .localized("name: %@"), name)) }
		if let id = rule.appIdentifier, !id.isEmpty { parts.append(String(format: .localized("id: %@"), id)) }
		if rule.certificateUUID != nil { parts.append(.localized("other certificate")) }
		if rule.removeTweaks { parts.append(.localized("no tweaks")) }
		return parts.isEmpty ? .localized("No changes") : parts.joined(separator: " • ")
	}
}

// MARK: - Rule
struct PresetRuleEditView: View {
	@Binding var rule: PresetRule
	let certificates: [CertificatePair]

	var body: some View {
		Form {
			Section {
				TextField("com.example.app", text: $rule.pattern)
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled()
			} header: {
				Text(.localized("Matches (bundle identifier or name)"))
			} footer: {
				Text(.localized("Use * as a wildcard, like com.google.*"))
			}

			Section(.localized("Changes for these apps")) {
				TextField(.localized("Name"), text: Binding(
					get: { rule.appName ?? "" },
					set: { rule.appName = $0.isEmpty ? nil : $0 }
				))
				TextField(.localized("Identifier"), text: Binding(
					get: { rule.appIdentifier ?? "" },
					set: { rule.appIdentifier = $0.isEmpty ? nil : $0 }
				))
				.textInputAutocapitalization(.never)
				.autocorrectionDisabled()

				Picker(.localized("Certificate"), selection: $rule.certificateUUID) {
					Text(.localized("Same as preset")).tag(String?.none)
					ForEach(certificates, id: \.uuid) { cert in
						Text(cert.nickname ?? .localized("Unknown")).tag(cert.uuid as String?)
					}
				}

				Toggle(.localized("Sign without tweaks"), isOn: $rule.removeTweaks)
			}
		}
		.navigationTitle(.localized("Rule"))
		.navigationBarTitleDisplayMode(.inline)
	}
}
