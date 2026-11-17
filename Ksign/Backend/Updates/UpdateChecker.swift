//
//  UpdateChecker.swift
//  Ksign
//
//  looks for app updates in the background (BGAppRefresh) and when the app comes to the foreground,
//  and sends a local notification for versions it has not told you about yet
//

import Foundation
import BackgroundTasks
import UserNotifications
import UIKit
import AltSourceKit

enum UpdateChecker {
	static var taskID: String { "\(Bundle.main.bundleIdentifier ?? "ksign").updateCheck" }

	static var isEnabled: Bool { UserDefaults.standard.bool(forKey: UpdateManager.notifyKey) }

	private static let _notifiedKey = "ksign.notifiedUpdates"
	private static let _lastCheckKey = "ksign.lastUpdateCheck"

	// MARK: Background task
	/// call from didFinishLaunching. The identifier has to be in Info.plist (BGTaskSchedulerPermittedIdentifiers):
	/// when the app was re-signed with another bundle identifier it is not, and registering would crash, so skip it
	static func register() {
		let permitted = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
		guard permitted.contains(taskID) else { return }

		BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
			guard let task = task as? BGAppRefreshTask else { return }
			handle(task)
		}
	}

	static func schedule() {
		guard isEnabled || CertificateWatcher.alertsOn else { return }
		let request = BGAppRefreshTaskRequest(identifier: taskID)
		request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60)
		try? BGTaskScheduler.shared.submit(request)
	}

	private static func handle(_ task: BGAppRefreshTask) {
		schedule()
		let work = Task { @MainActor in
			CertificateWatcher.scan()
			await check(force: true)
			task.setTaskCompleted(success: true)
		}
		task.expirationHandler = { work.cancel() }
	}

	// MARK: Check
	/// downloads every source again and notifies about updates that were not announced yet
	/// without `force` it runs at most once an hour (used when the app opens)
	@MainActor
	static func check(force: Bool = false) async {
		guard isEnabled else { return }

		let last = UserDefaults.standard.double(forKey: _lastCheckKey)
		if !force, Date().timeIntervalSince1970 - last < 3600 { return }
		UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: _lastCheckKey)

		let request = AltSource.fetchRequest()
		guard let sources = try? Storage.shared.context.fetch(request), !sources.isEmpty else { return }

		await SourcesViewModel.shared.fetchSources(sources, refresh: true)
		let repos = sources.compactMap { SourcesViewModel.shared.sources[$0] }
		let outdated = UpdateManager.outdated(in: repos)

		setBadge(outdated.count)

		var told = Set(UserDefaults.standard.stringArray(forKey: _notifiedKey) ?? [])
		let fresh = outdated.filter { !told.contains("\($0.id)@\($0.newVersion)") }
		guard !fresh.isEmpty else { return }

		fresh.forEach { told.insert("\($0.id)@\($0.newVersion)") }
		UserDefaults.standard.set(Array(told), forKey: _notifiedKey)

		let body: String
		if fresh.count == 1, let one = fresh.first {
			body = "\(one.app.currentName) \(one.localVersion) → \(one.newVersion)"
		} else {
			body = String(format: .localized("%lld apps have a new version"), fresh.count)
		}
		UpdateManager.notify(title: .localized("Updates available"), body: body, id: "ksign.updates")
	}

	// MARK: Alert when the app opens
	private static var _lastAlert = Date.distantPast

	/// apps with a new version, used for the "New update" alert every time the app opens
	/// (independent from the notification setting, at most once a minute)
	@MainActor
	static func updatesForAlert() async -> [OutdatedApp] {
		guard Date().timeIntervalSince(_lastAlert) > 60 else { return [] }

		let request = AltSource.fetchRequest()
		guard let sources = try? Storage.shared.context.fetch(request), !sources.isEmpty else { return [] }

		if SourcesViewModel.shared.sources.isEmpty {
			await SourcesViewModel.shared.fetchSources(sources)
		}
		let outdated = UpdateManager.outdated(in: sources.compactMap { SourcesViewModel.shared.sources[$0] })
		if !outdated.isEmpty { _lastAlert = Date() }
		return outdated
	}

	static func setBadge(_ count: Int) {
		if #available(iOS 16, *) {
			UNUserNotificationCenter.current().setBadgeCount(count)
		} else {
			DispatchQueue.main.async { UIApplication.shared.applicationIconBadgeNumber = count }
		}
	}

	/// asks for notification permission when the setting is turned on
	static func requestAuthorization(completion: @escaping (Bool) -> Void) {
		UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
			DispatchQueue.main.async { completion(granted) }
		}
	}
}
