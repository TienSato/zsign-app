//
//  SearchViewModel.swift
//  zsignapp
//  Created by Sato on 26/10/25.
//
//  Hai màn tìm kiếm (ứng dụng / nguồn) dùng chung một bộ vỏ: thanh tìm kiếm,
//  màn chờ, màn đang tìm, màn không có kết quả. Chỉ phần KẾT QUẢ là riêng:
//  ứng dụng dùng ScrollView + LazyVStack, nguồn dùng List (giữ kiểu inset).

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

// MARK: - Vỏ dùng chung cho hai màn tìm kiếm

/// Thanh tìm kiếm + ba trạng thái rỗng, phần kết quả do màn gọi truyền vào.
private struct SearchScaffold<Results: View>: View {
    @ObservedObject var viewModel: SearchViewModel
    @FocusState.Binding var isFocused: Bool
    
    let placeholder: LocalizedStringKey
    let idleTitle: LocalizedStringKey
    let idleMessage: LocalizedStringKey
    let idleFootnote: LocalizedStringKey
    let noResultsMessage: LocalizedStringKey
    let hasResults: Bool
    let results: Results
    
    init(viewModel: SearchViewModel,
         isFocused: FocusState<Bool>.Binding,
         placeholder: LocalizedStringKey,
         idleTitle: LocalizedStringKey,
         idleMessage: LocalizedStringKey,
         idleFootnote: LocalizedStringKey,
         noResultsMessage: LocalizedStringKey,
         hasResults: Bool,
         @ViewBuilder results: () -> Results) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self._isFocused = isFocused
        self.placeholder = placeholder
        self.idleTitle = idleTitle
        self.idleMessage = idleMessage
        self.idleFootnote = idleFootnote
        self.noResultsMessage = noResultsMessage
        self.hasResults = hasResults
        self.results = results()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            searchBar
            
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
            
            if viewModel.isSearching {
                searchingView
            } else if !viewModel.hasSearched {
                idleView
            } else if !hasResults {
                noResultsView
            } else {
                results
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
    }
    
    // MARK: - Thanh tìm kiếm
    @ViewBuilder
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: Theme.Metric.iconSize, weight: .semibold))
                .foregroundStyle(Theme.ink3)
            
            TextField(placeholder, text: $viewModel.searchText)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .focused($isFocused)
                .submitLabel(.search)
                .onSubmit {
                    viewModel.performSearch()
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.clearSearch()
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.ink3)
                }
                .buttonStyle(.plain)
            }
            
            Button {
                isFocused = false
                viewModel.performSearch()
            } label: {
                Text("Search")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(
                            viewModel.searchText.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Theme.ink3
                            : Color.accentColor
                        )
                    )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.searchText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, Theme.Metric.screenPadding)
        .padding(.vertical, 12)
        .background(Theme.card)
    }
    
    // MARK: - Chưa tìm lần nào
    @ViewBuilder
    private var idleView: some View {
        VStack(spacing: 10) {
            EmptyStateView(title: idleTitle,
                           systemImage: "magnifyingglass",
                           message: idleMessage,
                           style: .compact)
            
            Text(idleFootnote)
                .font(.caption)
                .foregroundStyle(Theme.ink3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Đang tìm
    @ViewBuilder
    private var searchingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.3)
            
            Text("Searching...")
                .font(.subheadline)
                .foregroundStyle(Theme.ink2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Không có kết quả
    @ViewBuilder
    private var noResultsView: some View {
        VStack(spacing: 16) {
            EmptyStateView(title: "No Results",
                           systemImage: "exclamationmark.magnifyingglass",
                           message: noResultsMessage,
                           style: .compact)
            
            Button {
                viewModel.clearSearch()
                isFocused = true
            } label: {
                Text("Try Another Search")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Nút "tìm lại từ đầu" dùng ở cuối cả hai danh sách kết quả.
private struct NewSearchButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise")
                Text("New Search")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
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
        SearchScaffold(
            viewModel: viewModel,
            isFocused: $isSearchFieldFocused,
            placeholder: "Enter app name...",
            idleTitle: "Search Apps",
            idleMessage: "Enter app name and tap Search",
            idleFootnote: "\(apps.count) apps available",
            noResultsMessage: "No apps found for \"\(viewModel.performedSearchText)\"",
            hasResults: !filteredApps.isEmpty
        ) {
            resultsGrid
        }
        .screenChrome("Search Apps")
        .onAppear {
            isSearchFieldFocused = true
        }
    }
    
    // MARK: - Results (ScrollView + LazyVStack)
    @ViewBuilder
    private var resultsGrid: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Text("RESULTS FOR \"\(viewModel.performedSearchText.uppercased())\"")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.ink2)
                    Spacer()
                    Text("\(filteredApps.count)")
                        .font(.footnote)
                        .foregroundStyle(Theme.ink3)
                }
                .padding(.horizontal, 4)
                .padding(.top, 12)
                .padding(.bottom, 8)
                
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredApps.enumerated()), id: \.element.currentUniqueId) { index, app in
                        VStack(spacing: 0) {
                            SourceAppRow(app: app)
                            if index < filteredApps.count - 1 {
                                Divider().padding(.leading, 84)
                            }
                        }
                    }
                }
                .cardStyle(padding: 0)
                
                NewSearchButton {
                    viewModel.clearSearch()
                    isSearchFieldFocused = true
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, Theme.Metric.screenPadding)
            .padding(.bottom, 32)
        }
        .background(Theme.canvas)
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
        SearchScaffold(
            viewModel: viewModel,
            isFocused: $isSearchFieldFocused,
            placeholder: "Enter source name...",
            idleTitle: "Search Sources",
            idleMessage: "Enter source name and tap Search",
            idleFootnote: "\(sources.count) sources available",
            noResultsMessage: "No sources found for \"\(viewModel.performedSearchText)\"",
            hasResults: !filteredSources.isEmpty
        ) {
            resultsList
        }
        .screenChrome("Search Sources")
        .onAppear {
            isSearchFieldFocused = true
        }
    }
    
    // MARK: - Results (List giữ nguyên)
    @ViewBuilder
    private var resultsList: some View {
        List {
            Section {
                ForEach(filteredSources) { source in
                    SourceCellView(source: source)
                        .listRowBackground(Theme.card)
                }
            } header: {
                HStack {
                    Text("RESULTS FOR \"\(viewModel.performedSearchText.uppercased())\"")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.ink2)
                    Spacer()
                    Text("\(filteredSources.count)")
                        .font(.footnote)
                        .foregroundStyle(Theme.ink3)
                }
            } footer: {
                if filteredSources.count > 0 {
                    NewSearchButton {
                        viewModel.clearSearch()
                        isSearchFieldFocused = true
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
    }
}
