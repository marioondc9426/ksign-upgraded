//
//  LogsManager.swift
//  Ksign
//
//  Created by Nagata Asami on 8/10/25.
//

import Foundation
import SwiftUI

final class LogsManager: ObservableObject {
	static let shared = LogsManager()

	@Published var entries: [LogEntry] = []
#if DEBUG
    @Published var isCapturing: Bool = false
#else
    @Published var isCapturing: Bool = true
#endif

	private var _stdoutPipe: Pipe?
	private static let maxEntries = 5000

	private init() { }

	func startCapture() {
		if _stdoutPipe != nil { return }
		isCapturing = true

		_stdoutPipe = Pipe()

		if let out = _stdoutPipe { _redirect(fd: STDOUT_FILENO, to: out) }

		_setupReadHandler(for: _stdoutPipe)
	}

	func stopCapture() {
		_stdoutPipe?.fileHandleForReading.readabilityHandler = nil

		_stdoutPipe = nil
		isCapturing = false
	}

	func clear() {
		DispatchQueue.main.async { self.entries.removeAll() }
	}

	func exportToText() -> String {
		let exportDateFormatter = DateFormatter()
		exportDateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
		let exportTimestamp = exportDateFormatter.string(from: Date())

		var logText = "Ksign Logs Export\n"
		logText += "Exported: \(exportTimestamp)\n"
		logText += "Total entries: \(entries.count)\n"
		logText += String(repeating: "=", count: 30) + "\n\n"
		logText += diagnosticsText() + "\n"
		logText += String(repeating: "=", count: 30) + "\n\n"

		for entry in entries {
			logText += "\(entry.message)\n"
		}

		return logText
	}

	private func _redirect(fd: Int32, to pipe: Pipe) {
		let handle = pipe.fileHandleForWriting
		dup2(handle.fileDescriptor, fd)
	}

	private func _setupReadHandler(for pipe: Pipe?) {
		guard let pipe else { return }
		pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
			guard let self else { return }
			
            let data = handle.availableData
			guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }

			let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
			guard !lines.isEmpty else { return }
            
			DispatchQueue.main.async {
				for line in lines { self.entries.append(LogEntry(message: line)) }
				// keep the newest lines only, a long session must not grow without limit
				if self.entries.count > Self.maxEntries {
					self.entries.removeFirst(self.entries.count - Self.maxEntries)
				}
			}
		}
	}

	// MARK: One-tap export
	/// device, app and install-server info, so one file is enough to understand a failed install or signing
	func diagnosticsText() -> String {
		var systemInfo = utsname()
		uname(&systemInfo)
		let model = withUnsafePointer(to: &systemInfo.machine) {
			$0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
		}
		let info = Bundle.main.infoDictionary
		let defaults = UserDefaults.standard
		let expiryFormatter = ISO8601DateFormatter()
		let appVersion = info?["CFBundleShortVersionString"] as? String ?? "?"
		let appBuild = info?["CFBundleVersion"] as? String ?? "?"
		let installMethod = defaults.integer(forKey: "Feather.installationMethod") == 1 ? "IDevice" : "Server"
		
		var text = "Diagnostics\n"
		text += "App: \(appVersion) (\(appBuild))\n"
		text += "Device: \(model), iOS \(UIDevice.current.systemVersion)\n"
		text += "Installation method: \(installMethod)\n"
		text += "Server method: configured \(ServerInstaller.getConfiguredServerMethod()), used \(ServerInstaller.getServerMethod()) (0 = Fully Local, 1 = Semi Local)\n"
		text += "Only localhost: \(ServerInstaller.getIPFix())\n"
		text += "Server host: \(ServerInstaller.sni)\n"
		text += "Wi-Fi address: \(ServerInstaller.getLocalAddress() ?? "none")\n"
		text += "SSL pack URL: \(ServerInstaller.getServerPackURL())\n"
		if let expiry = ServerInstaller.sslCertificateExpiry() {
			let expired = expiry < Date() ? " (EXPIRED)" : ""
			text += "SSL certificate expires: \(expiryFormatter.string(from: expiry))\(expired)\n"
		} else {
			text += "SSL certificate expires: unknown\n"
		}
		return text
	}
	
	/// writes the export to a temporary file and returns it
	func writeExportFile() -> URL? {
		let dateFormatter = DateFormatter()
		dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
		let fileURL = FileManager.default.temporaryDirectory
			.appendingPathComponent("Ksign-Logs-\(dateFormatter.string(from: Date())).txt")
		
		do {
			try exportToText().write(to: fileURL, atomically: true, encoding: .utf8)
			return fileURL
		} catch {
			print("Error exporting logs: \(error.localizedDescription)")
			return nil
		}
	}
	
	/// opens the share sheet with the log file (one tap from any error)
	func share() {
		guard let url = writeExportFile() else { return }
		DispatchQueue.main.async {
			UIActivityViewController.show(activityItems: [url])
		}
	}
	
	/// error alert with a "Share Logs" button next to the dismiss one
	func showErrorAlert(title: String, message: String, onDismiss: (() -> Void)? = nil) {
		let share = UIAlertAction(title: .localized("Share Logs"), style: .default) { _ in
			LogsManager.shared.share()
			onDismiss?()
		}
		let dismiss = UIAlertAction(title: .localized("Dismiss"), style: .cancel) { _ in
			onDismiss?()
		}
		
		UIAlertController.showAlert(title: title, message: message, actions: [share, dismiss])
	}
}
