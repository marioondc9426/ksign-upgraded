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

	func sign(_ app: AppInfoPresentable) {
		signApp = AnyApp(base: app)
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
			AppPresenter.shared.sign(app)
		}
	}
}
