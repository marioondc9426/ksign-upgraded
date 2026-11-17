//
//  TweakTestView.swift
//  Ksign
//
//  after signing for a test: checks the app, installs it, opens it and helps find out why it crashed
//
//  iOS does not let an app watch another app or read its crash logs, so what this does is:
//  1. look inside the signed app for the usual causes of a crash (TweakPreflight)
//  2. install it and open it
//  3. when you come back, ask if it worked, and if not show what is most likely wrong
//

import SwiftUI

struct TweakTestView: View {
	let app: AppInfoPresentable

	@Environment(\.dismiss) private var _dismiss
	@Environment(\.scenePhase) private var _scenePhase

	@State private var _issues: [PreflightIssue] = []
	@State private var _isChecking = true
	@State private var _installApp: AnyApp?
	@State private var _launched = false
	@State private var _askVerdict = false
	@State private var _crashed = false

	private var _executableName: String? {
		guard let dir = Storage.shared.getAppDirectory(for: app) else { return nil }
		return (NSDictionary(contentsOf: dir.appendingPathComponent("Info.plist"))?["CFBundleExecutable"]) as? String
	}

	private var _report: String {
		TweakPreflight.report(app: app, issues: _issues, options: SigningHistory.all().first?.options)
	}

	var body: some View {
		NavigationStack {
			List {
				Section {
					HStack(spacing: 12) {
						FRAppIconView(app: app, size: 50)
						VStack(alignment: .leading, spacing: 2) {
							Text(app.name ?? .localized("Unknown")).font(.headline)
							Text("\(app.version ?? "") • \(app.identifier ?? "")")
								.font(.footnote)
								.foregroundStyle(.secondary)
								.lineLimit(1)
						}
					}
				}

				Section {
					if _isChecking {
						HStack { ProgressView(); Text(.localized("Checking the app...")) }
					}
					ForEach(_issues) { issue in
						HStack(alignment: .top, spacing: 10) {
							Image(systemName: _icon(issue.level))
								.foregroundStyle(_color(issue.level))
							VStack(alignment: .leading, spacing: 3) {
								Text(issue.title).font(.subheadline.weight(.semibold))
								if !issue.detail.isEmpty {
									Text(issue.detail).font(.footnote).foregroundStyle(.secondary)
								}
							}
						}
					}
				} header: {
					Text(.localized("Check"))
				}

				Section {
					Button {
						_installApp = AnyApp(base: app)
					} label: {
						Label(.localized("Install"), systemImage: "square.and.arrow.down")
					}

					Button {
						_launched = true
						if let id = app.identifier { UIApplication.openApp(with: id) }
					} label: {
						Label(.localized("Open the app"), systemImage: "play.fill")
					}
				} header: {
					Text(.localized("Test"))
				} footer: {
					Text(.localized("Install it, open it and come back to Ksign. iOS does not let Ksign see another app crash, so it will ask you."))
				}

				if _crashed {
					Section {
						ForEach(_issues.filter { $0.level != .info }) { issue in
							Label(issue.title, systemImage: _icon(issue.level))
								.foregroundStyle(_color(issue.level))
						}
						if !_issues.contains(where: { $0.level != .info }) {
							Text(.localized("The check found nothing, so the crash is probably inside a tweak or the app does not like being re-signed. Try without tweaks first, then add them one by one."))
								.font(.footnote)
						}
						if let name = _executableName {
							Text(String(format: .localized("iOS keeps the crash log. Settings > Privacy & Security > Analytics & Improvements > Analytics Data, open the newest file starting with %@."), name))
								.font(.footnote)
						}
					} header: {
						Text(.localized("What to look at"))
					}
				}

				Section {
					Text(_report)
						.font(.system(.caption, design: .monospaced))
						.textSelection(.enabled)

					Button {
						UIPasteboard.general.string = _report
					} label: {
						Label(.localized("Copy report"), systemImage: "doc.on.doc")
					}
					Button {
						UIActivityViewController.show(activityItems: [_report])
					} label: {
						Label(.localized("Share report"), systemImage: "square.and.arrow.up")
					}
				} header: {
					Text(.localized("Report"))
				}
			}
			.navigationTitle(.localized("Test tweaks"))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) {
					Button(.localized("Done")) { _dismiss() }
				}
			}
			.sheet(item: $_installApp) { item in
				InstallPreviewView(app: item.base, isSharing: item.archive)
					.presentationDetents([.height(200)])
					.presentationDragIndicator(.visible)
			}
			.alert(.localized("Did it work?"), isPresented: $_askVerdict) {
				Button(.localized("Yes, it works")) { _crashed = false }
				Button(.localized("It crashed"), role: .destructive) { _crashed = true }
			} message: {
				Text(.localized("You opened the app from here. Tell Ksign how it went."))
			}
			.onChange(of: _scenePhase) { phase in
				if phase == .active, _launched {
					_launched = false
					_askVerdict = true
				}
			}
			.task {
				guard let dir = Storage.shared.getAppDirectory(for: app) else {
					_issues = [PreflightIssue(level: .error, title: .localized("App not found"), detail: "")]
					_isChecking = false
					return
				}
				let result = await Task.detached { TweakPreflight.run(appDirectory: dir) }.value
				_issues = result
				_isChecking = false
			}
		}
	}

	private func _icon(_ level: PreflightIssue.Level) -> String {
		switch level {
		case .error: return "xmark.octagon.fill"
		case .warning: return "exclamationmark.triangle.fill"
		case .info: return "checkmark.circle.fill"
		}
	}

	private func _color(_ level: PreflightIssue.Level) -> Color {
		switch level {
		case .error: return .red
		case .warning: return .orange
		case .info: return .green
		}
	}
}
