//
//  MultiCertificatePickerView.swift
//  Ksign
//
//  Pick several certificates for Multi Sign: every app is signed once per selected certificate.
//

import SwiftUI
import NimbleViews

struct MultiCertificatePickerView: View {
	@FetchRequest(
		entity: CertificatePair.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)],
		animation: .snappy
	) private var certificates: FetchedResults<CertificatePair>
	
	@Binding var selection: Set<Int>
	
	private var _toggleTitle: String {
		selection.isEmpty ? .localized("Select All") : .localized("Clear")
	}
	
	var body: some View {
		List {
			Section {
				Text(.localized("Each app is signed once for every selected certificate. Leave this empty to use only the certificate chosen above."))
					.font(.footnote)
					.foregroundStyle(.secondary)
			}
			
			Section {
				ForEach(Array(certificates.enumerated()), id: \.offset) { index, cert in
					Button {
						if selection.contains(index) {
							selection.remove(index)
						} else {
							selection.insert(index)
						}
					} label: {
						HStack {
							CertificatesCellView(cert: cert)
							Spacer()
							Image(systemName: selection.contains(index) ? "checkmark.circle.fill" : "circle")
								.foregroundStyle(selection.contains(index) ? Color.accentColor : Color.secondary)
						}
					}
					.buttonStyle(.plain)
				}
			}
		}
		.navigationTitle(.localized("Multi Sign"))
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Button(_toggleTitle) {
					if selection.isEmpty {
						selection = Set(certificates.indices)
					} else {
						selection.removeAll()
					}
				}
			}
		}
	}
}
