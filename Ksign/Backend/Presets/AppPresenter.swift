//
//  AppPresenter.swift
//  Ksign
//
//  lets any screen (Home, "open in Ksign", ...) open the signing screen and the tweak test
//  on top of whatever tab is showing
//

import Foundation
import CoreData

@MainActor
final class AppPresenter: ObservableObject {
	static let shared = AppPresenter()

	@Published var signApp: AnyApp?
	/// the signed app being tested (shows the tweak test screen)
	@Published var testApp: AnyApp?

	/// when true, finishing the signing opens the tweak test for the new signed app
	var isTestFlow = false

	func sign(_ app: AppInfoPresentable, test: Bool) {
		isTestFlow = test
		signApp = AnyApp(base: app)
	}

	/// called when a signing finished
	func signingFinished() {
		guard isTestFlow else { return }
		isTestFlow = false
		guard let newest = Self.newestSigned() else { return }
		// the signing screen is still closing
		Task { @MainActor in
			try? await Task.sleep(nanoseconds: 700_000_000)
			self.testApp = AnyApp(base: newest)
		}
	}

	static func newestSigned() -> Signed? {
		let request = NSFetchRequest<Signed>(entityName: "Signed")
		request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
		request.fetchLimit = 1
		return try? Storage.shared.context.fetch(request).first
	}

	static func newestImportedApp() -> Imported? {
		let request = NSFetchRequest<Imported>(entityName: "Imported")
		request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
		request.fetchLimit = 1
		return try? Storage.shared.context.fetch(request).first
	}

	/// an ipa was opened from another app (share sheet, Files): go straight to signing it
	nonisolated static func openSignForNewestImported() {
		Task { @MainActor in
			guard let app = newestImportedApp() else { return }
			AppPresenter.shared.sign(app, test: false)
		}
	}
}
