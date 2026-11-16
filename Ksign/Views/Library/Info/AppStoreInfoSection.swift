//
//  AppStoreInfoSection.swift
//  Ksign
//
//  Library info: the description from your sources plus the App Store description and screenshots.
//

import SwiftUI
import NimbleViews
import AltSourceKit

// MARK: - Model
struct AppStoreLookup {
	var name: String?
	var developer: String?
	var description: String?
	var releaseNotes: String?
	var rating: Double?
	var ratingCount: Int?
	var screenshots: [URL]
	var storeURL: URL?
	
	/// iTunes Lookup API, no key needed. Finds an app by bundle identifier.
	static func fetch(bundleID: String) async -> AppStoreLookup? {
		let region = Locale.current.region?.identifier.lowercased() ?? "us"
		
		// the identifier may carry a suffix added by re-signing, so also try the shorter ones
		var candidates = [bundleID]
		var parts = bundleID.split(separator: ".").map(String.init)
		while parts.count > 3 {
			parts.removeLast()
			candidates.append(parts.joined(separator: "."))
		}
		
		for id in candidates {
			for country in [region, "us"] {
				if let found = await _lookup(bundleID: id, country: country) {
					return found
				}
			}
		}
		return nil
	}
	
	private static func _lookup(bundleID: String, country: String) async -> AppStoreLookup? {
		var comps = URLComponents(string: "https://itunes.apple.com/lookup")
		comps?.queryItems = [
			URLQueryItem(name: "bundleId", value: bundleID),
			URLQueryItem(name: "country", value: country)
		]
		guard let url = comps?.url else { return nil }
		
		do {
			let (data, _) = try await URLSession.shared.data(from: url)
			guard
				let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
				let results = root["results"] as? [[String: Any]],
				let first = results.first
			else { return nil }
			
			let phone = (first["screenshotUrls"] as? [String] ?? []).compactMap { URL(string: $0) }
			let pad = (first["ipadScreenshotUrls"] as? [String] ?? []).compactMap { URL(string: $0) }
			
			return AppStoreLookup(
				name: first["trackName"] as? String,
				developer: first["artistName"] as? String,
				description: first["description"] as? String,
				releaseNotes: first["releaseNotes"] as? String,
				rating: first["averageUserRating"] as? Double,
				ratingCount: first["userRatingCount"] as? Int,
				screenshots: phone.isEmpty ? pad : phone,
				storeURL: (first["trackViewUrl"] as? String).flatMap { URL(string: $0) }
			)
		} catch {
			return nil
		}
	}
}

// MARK: - View
struct AppStoreInfoSection: View {
	var bundleID: String?
	
	@ObservedObject private var _sources = SourcesViewModel.shared
	@State private var _lookup: AppStoreLookup?
	@State private var _isLoading = true
	@State private var _expandedSource = false
	@State private var _expandedStore = false
	
	/// the same app in one of your sources (matched by bundle identifier)
	private var _sourceApp: ASRepository.App? {
		guard let bundleID else { return nil }
		for repo in _sources.sources.values {
			if let app = repo.apps.first(where: { $0.id == bundleID }) {
				return app
			}
		}
		return nil
	}
	
	private var _sourceDescription: String? {
		guard let app = _sourceApp else { return nil }
		let text = app.localizedDescription ?? app.description ?? app.subtitle
		return (text?.isEmpty == false) ? text : nil
	}
	
	var body: some View {
		Group {
			if let text = _sourceDescription {
				Section(.localized("Description")) {
					_expandableText(text, expanded: $_expandedSource)
				}
			}
			
			if let lookup = _lookup {
				Section(.localized("App Store")) {
					if let developer = lookup.developer {
						LabeledContent(String.localized("Developer")) { Text(developer) }
					}
					
					if let rating = lookup.rating {
						LabeledContent(String.localized("Rating")) {
							Text(String(format: "%.1f", rating) + (lookup.ratingCount.map { " (\($0))" } ?? ""))
						}
					}
					
					if let text = lookup.description, !text.isEmpty {
						_expandableText(text, expanded: $_expandedStore)
					}
					
					if let notes = lookup.releaseNotes, !notes.isEmpty {
						VStack(alignment: .leading, spacing: 4) {
							Text(.localized("What's New"))
								.font(.footnote.weight(.semibold))
							Text(notes)
								.font(.footnote)
								.foregroundStyle(.secondary)
						}
					}
					
					if let url = lookup.storeURL {
						Button(.localized("Open in App Store"), systemImage: "arrow.up.forward.app") {
							UIApplication.open(url)
						}
					}
				}
				
				if !lookup.screenshots.isEmpty {
					Section(.localized("Screenshots")) {
						ScrollView(.horizontal, showsIndicators: false) {
							HStack(spacing: 10) {
								ForEach(lookup.screenshots, id: \.self) { url in
									AsyncImage(url: url) { phase in
										if let image = phase.image {
											image.resizable().scaledToFit()
										} else if phase.error != nil {
											Color.secondary.opacity(0.15)
										} else {
											ZStack { Color.secondary.opacity(0.1); ProgressView() }
										}
									}
									.frame(height: 360)
									.frame(minWidth: 160)
									.clipShape(RoundedRectangle(cornerRadius: 14))
								}
							}
							.padding(.vertical, 4)
						}
						.listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
					}
				}
			} else if _isLoading, bundleID != nil {
				Section(.localized("App Store")) {
					HStack(spacing: 8) {
						ProgressView()
						Text(.localized("Fetching..."))
							.foregroundStyle(.secondary)
					}
				}
			}
		}
		.task(id: bundleID) {
			guard let bundleID else {
				_isLoading = false
				return
			}
			_isLoading = true
			_lookup = await AppStoreLookup.fetch(bundleID: bundleID)
			_isLoading = false
		}
	}
	
	@ViewBuilder
	private func _expandableText(_ text: String, expanded: Binding<Bool>) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(text)
				.font(.callout)
				.lineLimit(expanded.wrappedValue ? nil : 6)
			
			if text.count > 260 {
				Button(expanded.wrappedValue ? String.localized("Less") : String.localized("More")) {
					withAnimation { expanded.wrappedValue.toggle() }
				}
				.font(.footnote.weight(.semibold))
			}
		}
	}
}
