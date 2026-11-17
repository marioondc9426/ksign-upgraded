//
//  SourceAppsView.swift
//  Feather
//
//  Created by samara on 1.05.2025.
//

import SwiftUI
import AltSourceKit
import NimbleViews
import UIKit

// MARK: - Extension: View (Enil)
extension SourceAppsView {
    enum SortOption: String, CaseIterable {
        case `default` = "default"
        case name
        case date
        
        var displayName: String {
            switch self {
            case .default:  .localized("Default")
            case .name:     .localized("Name")
            case .date:     .localized("Date")
            }
        }
    }
}

// MARK: - View
struct SourceAppsView: View {
    @AppStorage("Feather.sortOptionRawValue") private var _sortOptionRawValue: String = SortOption.default.rawValue
    @AppStorage("Feather.sortAscending") private var _sortAscending: Bool = true
    
    @State private var _sortOption: SortOption = .default
    @State private var _selectedRoute: SourceAppRoute?
    
    @State var isLoading = true
    @State var hasLoadedOnce = false
    @State private var _searchText = ""
    var fromAppStore: Bool = false
    
    private var _navigationTitle: String {
        if fromAppStore {
            return .localized("App Store")
        } else if object.count == 1 {
            return object[0].name ?? .localized("Unknown")
        } else {
            return .localized("%lld Sources", arguments: object.count)
        }
    }
    
    var object: [AltSource]
    @ObservedObject var viewModel: SourcesViewModel
    
    /// repositories that already finished downloading (grows while fetching)
    private var _sources: [ASRepository]? {
        let loaded = object.compactMap { viewModel.sources[$0] }
        return loaded.isEmpty ? nil : loaded
    }
    
    @FetchRequest(
        entity: AltSource.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)],
        animation: .snappy
    ) private var _allSources: FetchedResults<AltSource>
    
    // MARK: Body
    var body: some View {
        ZStack {
            if
                let _sources,
                !_sources.isEmpty
            {
                SourceAppsTableRepresentableView(
                    sources: _sources,
                    searchText: $_searchText,
                    sortOption: $_sortOption,
                    sortAscending: $_sortAscending,
                    onSelect: {self._selectedRoute = $0}
                )
                .ignoresSafeArea()
            } else {
                if #available(iOS 17, *) {
                    ContentUnavailableView {
                        ProgressView()
                        Label(_fetchingTitle, systemImage: "")
                    } description: {
                        Text(.localized("Stuck? Check if you have any sources added."))
                    }
                }
                else { ProgressView() }
            }
        }
        .overlay(alignment: .bottom) {
            // apps are already listed, but some sources are still downloading
            if _sources != nil, viewModel.isFetching {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(_fetchingTitle)
                        .font(.footnote)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.isFetching)
        .navigationTitle(_navigationTitle)
        .searchable(text: $_searchText, placement: .platform())
        .toolbarTitleMenu {
            if
                let _sources,
                _sources.count == 1
            {
                if let url = _sources[0].website {
                    Button(.localized("Visit Website"), systemImage: "globe") {
                        UIApplication.open(url)
                    }
                }
                
                if let url = _sources[0].patreonURL {
                    Button(.localized("Visit Patreon"), systemImage: "dollarsign.circle") {
                        UIApplication.open(url)
                    }
                }
            }
            
            Divider()
            
            Button(.localized("Copy"), systemImage: "doc.on.doc") {
                UIPasteboard.general.string = object.map {
                    $0.sourceURL!.absoluteString
                }.joined(separator: "\n")
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
        .toolbar {
            if fromAppStore {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SourcesView()
                    } label: {
                        Text(.localized("Sources"))
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    UpdatesLinkButton()
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    UnlockStoreButton()
                }
            }
            
            NBToolbarButton(
                systemImage: "arrow.trianglehead.2.counterclockwise.rotate.90",
                style: .icon,
                placement: .topBarTrailing
            ) {
                Task {
                    await viewModel.fetchSources(_allSources, refresh: true)
                }
            }
            
            NBToolbarMenu(
                systemImage: "line.3.horizontal.decrease",
                style: .icon,
                placement: .topBarTrailing
            ) {
                _sortActions()
            }
        }
        .onAppear {
            _sortOption = SortOption(rawValue: _sortOptionRawValue) ?? .default
        }
        .onChange(of: _sortOption) { newValue in
            _sortOptionRawValue = newValue.rawValue
        }
        .navigationDestinationIfAvailable(item: $_selectedRoute) { route in
            SourceAppsDetailView(source: route.source, app: route.app)
        }
        
    }
    
    private var _fetchingTitle: String {
        guard viewModel.isFetching, viewModel.fetchTotal > 0 else { return .localized("Fetching...") }
        return String(format: .localized("Fetching... %lld of %lld"), viewModel.fetchDone, viewModel.fetchTotal)
    }
    
    struct SourceAppRoute: Identifiable, Hashable {
        let source: ASRepository
        let app: ASRepository.App
        let id: String = UUID().uuidString
    }
}

// MARK: - Extension: View (Sort)
extension SourceAppsView {
    @ViewBuilder
    private func _sortActions() -> some View {
        Section(.localized("Filter by")) {
            ForEach(SortOption.allCases, id: \.displayName) { opt in
                _sortButton(for: opt)
            }
        }
    }
    
    private func _sortButton(for option: SortOption) -> some View {
        Button {
            if _sortOption == option {
                _sortAscending.toggle()
            } else {
                _sortOption = option
                _sortAscending = true
            }
        } label: {
            HStack {
                Text(option.displayName)
                Spacer()
                if _sortOption == option {
                    Image(systemName: _sortAscending ? "chevron.up" : "chevron.down")
                }
            }
        }
    }
}

import SwiftUI

extension View {
    @ViewBuilder
    func navigationDestinationIfAvailable<Item: Identifiable & Hashable, Destination: View>(
        item: Binding<Item?>,
        @ViewBuilder destination: @escaping (Item) -> Destination
    ) -> some View {
        if #available(iOS 17, *) {
            self.navigationDestination(item: item, destination: destination)
        } else {
            self
        }
    }
}
