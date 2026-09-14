//
//  SearchViewModel.swift
//  zsignapp
//  Created by Sato on 26/10/25.

import SwiftUI
import AltSourceKit
import Combine

// MARK: - Search View Model
class SearchViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var performedSearchText: String = ""
    @Published var isSearching: Bool = false
    
    var hasSearched: Bool {
        !performedSearchText.isEmpty
    }
    
    func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            return
        }
        
        isSearching = true
        performedSearchText = searchText
        
        // Simulate search delay for better UX
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.isSearching = false
        }
    }
    
    func clearSearch() {
        searchText = ""
        performedSearchText = ""
        isSearching = false
    }
}

// MARK: - Search Apps View (Grid Layout)
struct SearchAppsView: View {
    let apps: [ASRepository.App]
    
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = SearchViewModel()
    @FocusState private var isSearchFieldFocused: Bool
    
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    private var filteredApps: [ASRepository.App] {
        guard viewModel.hasSearched else {
            return []
        }
        
        let searchTerm = viewModel.performedSearchText.trimmingCharacters(in: .whitespaces)
        guard !searchTerm.isEmpty else {
            return []
        }
        
        return apps.filter {
            $0.name?.localizedCaseInsensitiveContains(searchTerm) ?? false
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom Search Bar
            searchBar
            
            Divider()
            
            // Content
            if viewModel.isSearching {
                searchingView
            } else if !viewModel.hasSearched {
                initialView
            } else if filteredApps.isEmpty {
                noResultsView
            } else {
                resultsGrid
            }
        }
        .navigationTitle("Search Apps")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isSearchFieldFocused = true
        }
    }
    
    // MARK: - Search Bar
    @ViewBuilder
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Enter app name...", text: $viewModel.searchText)
                .focused($isSearchFieldFocused)
                .submitLabel(.search)
                .onSubmit {
                    viewModel.performSearch()
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.clearSearch()
                    isSearchFieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
            
            Button {
                isSearchFieldFocused = false
                viewModel.performSearch()
            } label: {
                Text("Search")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        viewModel.searchText.trimmingCharacters(in: .whitespaces).isEmpty
                        ? Color.gray
                        : Color.accentColor
                    )
                    .cornerRadius(8)
            }
            .disabled(viewModel.searchText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
        .background(Color(.systemBackground))
    }
    
    // MARK: - Initial View
    @ViewBuilder
    private var initialView: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 70))
                .foregroundColor(.gray)
            
            Text("Search Apps")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Enter app name and tap Search")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Text("\(apps.count) apps available")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Searching View
    @ViewBuilder
    private var searchingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Searching...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - No Results View
    @ViewBuilder
    private var noResultsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.magnifyingglass")
                .font(.system(size: 70))
                .foregroundColor(.orange)
            
            Text("No Results")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("No apps found for \"\(viewModel.performedSearchText)\"")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button {
                viewModel.clearSearch()
                isSearchFieldFocused = true
            } label: {
                Text("Try Another Search")
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Results Grid
    @ViewBuilder
    private var resultsGrid: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("RESULTS FOR \"\(viewModel.performedSearchText.uppercased())\"")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(filteredApps.count)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color(.systemGroupedBackground))
                
                // Danh sách
                LazyVStack(spacing: 0) {
                    ForEach(filteredApps, id: \.currentUniqueId) { app in
                        VStack(spacing: 0) {
                            SourceAppRow(app: app)
                            Divider().padding(.leading, 84)
                        }
                    }
                }
                
                // New Search Button
                Button {
                    viewModel.clearSearch()
                    isSearchFieldFocused = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("New Search")
                    }
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
                }
                .padding(.top, 20)
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Search Sources View (Keep List)
struct SearchSourcesView: View {
    let sources: [AltSource]
    
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = SearchViewModel()
    @FocusState private var isSearchFieldFocused: Bool
    
    private var filteredSources: [AltSource] {
        guard viewModel.hasSearched else {
            return []
        }
        
        let searchTerm = viewModel.performedSearchText.trimmingCharacters(in: .whitespaces)
        guard !searchTerm.isEmpty else {
            return []
        }
        
        return sources.filter {
            $0.name?.localizedCaseInsensitiveContains(searchTerm) ?? false
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom Search Bar
            searchBar
            
            Divider()
            
            // Content
            if viewModel.isSearching {
                searchingView
            } else if !viewModel.hasSearched {
                initialView
            } else if filteredSources.isEmpty {
                noResultsView
            } else {
                resultsList
            }
        }
        .navigationTitle("Search Sources")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isSearchFieldFocused = true
        }
    }
    
    // MARK: - Search Bar
    @ViewBuilder
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Enter source name...", text: $viewModel.searchText)
                .focused($isSearchFieldFocused)
                .submitLabel(.search)
                .onSubmit {
                    viewModel.performSearch()
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.clearSearch()
                    isSearchFieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
            
            Button {
                isSearchFieldFocused = false
                viewModel.performSearch()
            } label: {
                Text("Search")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        viewModel.searchText.trimmingCharacters(in: .whitespaces).isEmpty
                        ? Color.gray
                        : Color.accentColor
                    )
                    .cornerRadius(8)
            }
            .disabled(viewModel.searchText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
        .background(Color(.systemBackground))
    }
    
    // MARK: - Initial View
    @ViewBuilder
    private var initialView: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 70))
                .foregroundColor(.gray)
            
            Text("Search Sources")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Enter source name and tap Search")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Text("\(sources.count) sources available")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Searching View
    @ViewBuilder
    private var searchingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Searching...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - No Results View
    @ViewBuilder
    private var noResultsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.magnifyingglass")
                .font(.system(size: 70))
                .foregroundColor(.orange)
            
            Text("No Results")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("No sources found for \"\(viewModel.performedSearchText)\"")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button {
                viewModel.clearSearch()
                isSearchFieldFocused = true
            } label: {
                Text("Try Another Search")
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Results List
    @ViewBuilder
    private var resultsList: some View {
        List {
            Section {
                ForEach(filteredSources) { source in
                    SourceCellView(source: source)
                }
            } header: {
                HStack {
                    Text("RESULTS FOR \"\(viewModel.performedSearchText.uppercased())\"")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(filteredSources.count)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } footer: {
                if filteredSources.count > 0 {
                    Button {
                        viewModel.clearSearch()
                        isSearchFieldFocused = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("New Search")
                        }
                        .font(.subheadline)
                        .foregroundColor(.accentColor)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}
