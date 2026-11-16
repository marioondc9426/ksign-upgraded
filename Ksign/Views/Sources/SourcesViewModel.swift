//
//  SourcesViewModel.swift
//  Feather
//
//  Created by samara on 30.04.2025.
//

import Foundation
import AltSourceKit
import SwiftUI
import NimbleJSON

// MARK: - Class
final class SourcesViewModel: ObservableObject {
	static let shared = SourcesViewModel()

	typealias RepositoryDataHandler = Result<ASRepository, Error>

	private let _dataService = NBFetchService()

	/// how many sources are downloaded at the same time
	static let maxConcurrentFetches = 16

	var isFinished = true
	@Published var sources: [AltSource: ASRepository] = [:]
	
	// progress of the current fetch, so the App Store can show "x of y" while apps appear
	@Published var isFetching = false
	@Published var fetchDone = 0
	@Published var fetchTotal = 0
	
	// a fetch asked for while another one is running is remembered and run right after it
	// (adding a source while the list was loading used to be ignored until a manual refresh)
	private var _pendingSources: [AltSource]?
	private var _pendingRefresh = false
	
	/// registers a repository that was already downloaded (e.g. while validating a new source), so it shows up at once
	/// call it on the main thread
	func prime(_ source: AltSource, with repository: ASRepository) {
		sources[source] = repository
	}
	
	func fetchSources(_ sources: FetchedResults<AltSource>, refresh: Bool = false, maxConcurrent: Int = SourcesViewModel.maxConcurrentFetches) async {
		await fetchSources(Array(sources), refresh: refresh, maxConcurrent: maxConcurrent)
	}
	
	func fetchSources(_ sourcesArray: [AltSource], refresh: Bool = false, maxConcurrent: Int = SourcesViewModel.maxConcurrentFetches) async {
		guard isFinished else {
			_pendingSources = sourcesArray
			_pendingRefresh = _pendingRefresh || refresh
			return
		}
		
		// isfinished is used to prevent multiple fetches at the same time
		isFinished = false
		
		// only download what is missing, a new source no longer re-downloads every other source.
		// a refresh downloads everything again but keeps the old data on screen until each repository is replaced
		let wanted = Set(sourcesArray)
		let toFetch = refresh ? sourcesArray : sourcesArray.filter { self.sources[$0] == nil }
		let total = toFetch.count
		
		await MainActor.run {
			// drop sources that were deleted
			for key in self.sources.keys where !wanted.contains(key) {
				self.sources.removeValue(forKey: key)
			}
			self.fetchDone = 0
			self.fetchTotal = total
			self.isFetching = total > 0
		}
		
		// sliding window: always keep up to `maxConcurrent` downloads running (no waiting for a whole batch)
		// and publish every repository the moment it finishes, so the app list fills up while fetching
		if total > 0 {
			await withTaskGroup(of: (AltSource, ASRepository?).self) { group in
				var next = 0
				
				while next < min(maxConcurrent, total) {
					let source = toFetch[next]
					next += 1
					group.addTask { await self._fetchRepository(source) }
				}
				
				for await (source, repo) in group {
					await MainActor.run {
						if let repo {
							self.sources[source] = repo
						}
						self.fetchDone += 1
					}
					
					if next < total {
						let nextSource = toFetch[next]
						next += 1
						group.addTask { await self._fetchRepository(nextSource) }
					}
				}
			}
		}
		
		await MainActor.run {
			self.isFetching = false
		}
		isFinished = true
		
		if let pending = _pendingSources {
			let pendingRefresh = _pendingRefresh
			_pendingSources = nil
			_pendingRefresh = false
			await fetchSources(pending, refresh: pendingRefresh, maxConcurrent: maxConcurrent)
		}
	}
	
	private func _fetchRepository(_ source: AltSource) async -> (AltSource, ASRepository?) {
		guard let url = source.sourceURL else {
			return (source, nil)
		}

		return await withCheckedContinuation { continuation in
			self._dataService.fetch(from: url) { (result: RepositoryDataHandler) in
				switch result {
				case .success(let repo):
					continuation.resume(returning: (source, repo))
				case .failure(_):
					continuation.resume(returning: (source, nil))
				}
			}
		}
	}
}
