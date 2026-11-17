//
//  NewPresetSheet.swift
//  Ksign
//
//  the popup that opens with "Add preset": name, description and the tweaks it injects
//

import SwiftUI

struct NewPresetSheet: View {
	@Environment(\.dismiss) private var _dismiss

	@State private var _name = ""
	@State private var _desc = ""
	@State private var _options = OptionsManager.shared.options

	/// called with the finished preset
	let onAdd: (String, String, Options) -> Void

	var body: some View {
		NavigationStack {
			Form {
				Section(.localized("Preset")) {
					TextField(.localized("Name"), text: $_name)
					TextField(.localized("Description"), text: $_desc, axis: .vertical)
						.lineLimit(1...4)
				}

				Section {
					if _options.injectionFiles.isEmpty {
						Text(.localized("No tweaks"))
							.foregroundStyle(.secondary)
					}
					ForEach(_options.injectionFiles, id: \.absoluteString) { tweak in
						Label(tweak.lastPathComponent, systemImage: "puzzlepiece.extension")
					}
					NavigationLink {
						SigningTweaksView(options: $_options)
					} label: {
						Label(.localized("Add or remove tweaks"), systemImage: "plus.circle")
					}
				} header: {
					Text(.localized("Tweaks"))
				} footer: {
					Text(.localized("These tweaks are injected every time the preset is used. The other options start from your current signing options and can be changed later."))
				}
			}
			.navigationTitle(.localized("New Preset"))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					Button(.localized("Cancel")) { _dismiss() }
				}
				ToolbarItem(placement: .topBarTrailing) {
					Button(.localized("Add")) {
						onAdd(_name.trimmingCharacters(in: .whitespacesAndNewlines), _desc.trimmingCharacters(in: .whitespacesAndNewlines), _options)
						_dismiss()
					}
					.disabled(_name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
				}
			}
		}
	}
}
