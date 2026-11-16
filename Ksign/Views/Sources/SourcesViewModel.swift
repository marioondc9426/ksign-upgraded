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

	func fetchSources(_ sources: FetchedResults<AltSource>, refresh: Bool = false, maxConcurrent: Int = SourcesViewModel.maxConcurrentFetches) async {
		guard isFinished else { return }

		// check if sources to be fetched are the same as before, if yes, return
		// also skip check if refresh is true
		if !refresh, sources.allSatisfy({ self.sources[$0] != nil }) { return }

		// isfinished is used to prevent multiple fetches at the same time
		isFinished = false
		defer { isFinished = true }

		let sourcesArray = Array(sources)
		let total = sourcesArray.count

		await MainActor.run {
			self.sources = [:]
			self.fetchDone = 0
			self.fetchTotal = total
			self.isFetching = total > 0
		}

		// sliding window: always keep up to `maxConcurrent` downloads running (no waiting for a whole batch)
		// and publish every repository the moment it finishes, so the app list fills up while fetching
		await withTaskGroup(of: (AltSource, ASRepository?).self) { group in
			var next = 0

			while next < min(maxConcurrent, total) {
				let source = sourcesArray[next]
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
					let nextSource = sourcesArray[next]
					next += 1
					group.addTask { await self._fetchRepository(nextSource) }
				}
			}
		}

		await MainActor.run {
			self.isFetching = false
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
