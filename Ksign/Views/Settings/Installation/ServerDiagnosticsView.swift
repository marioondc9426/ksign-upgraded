//
//  ServerDiagnosticsView.swift
//  Ksign
//
//  quick look at everything the local install server depends on
//

import SwiftUI
import NimbleViews

struct ServerDiagnosticsView: View {
	@State private var _packStatus: String?
	@State private var _isTestingPack = false
	@State private var _refreshStatus: String?
	@State private var _tick = 0   // bumps to re-read everything

	private var _expiry: Date? { ServerInstaller.sslCertificateExpiry() }

	var body: some View {
		let _ = _tick

		NBList(.localized("Server Diagnostics")) {
			Section(.localized("Method")) {
				_row(.localized("Chosen"), ServerInstaller.getConfiguredServerMethod() == 0 ? .localized("Fully Local") : .localized("Semi Local"))
				_row(.localized("Actually used"), ServerInstaller.getServerMethod() == 0 ? .localized("Fully Local") : .localized("Semi Local"))
				_row(.localized("Only use localhost"), ServerInstaller.getIPFix() ? .localized("On") : .localized("Off"))
			}

			Section(.localized("Address")) {
				_row(.localized("Host used"), ServerInstaller.sni)
				_row(.localized("Wi-Fi address"), ServerInstaller.getLocalAddress() ?? .localized("None (no Wi-Fi?)"))
				_row(.localized("Certificate name"), ServerInstaller.readCommonName() ?? .localized("Unknown"))
			}

			Section(.localized("SSL certificate")) {
				_row(.localized("Files found"), _filesFound ? .localized("Yes") : .localized("No"))
				_row(.localized("Loads"), _tlsLoads)
				if let date = _expiry {
					_row(.localized("Expires"), date.formatted(date: .abbreviated, time: .omitted))
					_row(.localized("Days left"), _daysLeft(date))
				} else {
					_row(.localized("Expires"), .localized("Unknown"))
				}
			} footer: {
				Text(.localized("Fully Local needs a valid certificate. When it is expired Ksign falls back to Semi Local by itself."))
			}

			Section(.localized("Certificate pack")) {
				_row(.localized("URL"), ServerInstaller.getServerPackURL())

				Button {
					_testPack()
				} label: {
					HStack {
						Label(.localized("Test download"), systemImage: "network")
						if _isTestingPack { Spacer(); ProgressView() }
					}
				}
				.disabled(_isTestingPack)
				if let _packStatus { Text(_packStatus).font(.footnote).foregroundStyle(.secondary) }

				#if SERVER
				Button {
					_refresh()
				} label: {
					Label(.localized("Download certificate again"), systemImage: "arrow.triangle.2.circlepath")
				}
				if let _refreshStatus { Text(_refreshStatus).font(.footnote).foregroundStyle(.secondary) }
				#endif
			}
		}
	}

	private func _row(_ title: String, _ value: String) -> some View {
		LabeledContent(title) {
			Text(value)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.trailing)
				.textSelection(.enabled)
		}
	}

	private var _filesFound: Bool {
		ServerInstaller.getUrl("server", ext: "crt") != nil && ServerInstaller.getUrl("server", ext: "pem") != nil
	}

	private var _tlsLoads: String {
		do {
			return try ServerInstaller.tls() != nil ? .localized("Yes") : .localized("No")
		} catch {
			return error.localizedDescription
		}
	}

	private func _daysLeft(_ date: Date) -> String {
		let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
		return days < 0 ? .localized("Expired") : "\(days)"
	}

	private func _testPack() {
		guard let url = URL(string: ServerInstaller.getServerPackURL()) else {
			_packStatus = .localized("The URL is not valid")
			return
		}
		_isTestingPack = true
		_packStatus = nil
		let started = Date()

		URLSession.shared.dataTask(with: url) { data, response, error in
			DispatchQueue.main.async {
				_isTestingPack = false
				if let error {
					_packStatus = error.localizedDescription
				} else if let http = response as? HTTPURLResponse {
					let ms = Int(Date().timeIntervalSince(started) * 1000)
					let size = ByteCountFormatter.string(fromByteCount: Int64(data?.count ?? 0), countStyle: .file)
					_packStatus = "HTTP \(http.statusCode) • \(size) • \(ms) ms"
				}
			}
		}.resume()
	}

	#if SERVER
	private func _refresh() {
		_refreshStatus = .localized("Downloading...")
		FR.downloadSSLCertificates(from: ServerInstaller.getServerPackURL()) { ok in
			DispatchQueue.main.async {
				_refreshStatus = ok ? .localized("Done") : .localized("Failed")
				_tick += 1
			}
		}
	}
	#endif
}
