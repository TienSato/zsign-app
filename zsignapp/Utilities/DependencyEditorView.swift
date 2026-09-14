//
//  DependencyEditorView.swift
//  zsignapp
//
//  Created by Sato on 26/10/25.
//

import SwiftUI

struct DependencyEditorView: View {
    let fileURL: URL
    @StateObject private var viewModel: DependencyEditorViewModel
    @Environment(\.dismiss) private var dismiss
    
    init(fileURL: URL) {
        self.fileURL = fileURL
        _viewModel = StateObject(wrappedValue: DependencyEditorViewModel(fileURL: fileURL))
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                
                if viewModel.isLoading {
                    ProgressView("Loading dependencies...")
                } else if viewModel.dependencies.isEmpty {
                    emptyStateView
                } else {
                    dependencyListView
                }
            }
            .navigationTitle("Dependencies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An error occurred")
            }
            .alert("Edit Dependency", isPresented: $viewModel.showEditAlert) {
                TextField("New path", text: $viewModel.newPath)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                
                Button("Cancel", role: .cancel) {
                    viewModel.newPath = ""
                }
                
                Button("Replace") {
                    Task {
                        await viewModel.replaceDependency()
                    }
                }
            } message: {
                if let old = viewModel.selectedDependency {
                    Text("Replace:\n\(old)\n\nWith:")
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "link.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Dependencies")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("This dylib has no external dependencies")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    private var dependencyListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                listHeader
                
                ForEach(Array(viewModel.dependencies.enumerated()), id: \.offset) { index, dep in
                    dependencyRow(dep, index: index)
                }
            }
        }
    }
    
    private var listHeader: some View {
        HStack {
            Text("DEPENDENCIES (\(viewModel.dependencies.count))")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
    
    private func dependencyRow(_ dependency: String, index: Int) -> some View {
        Button {
            viewModel.selectDependencyForEdit(dependency)
        } label: {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(dependencyColor(dependency).opacity(0.15))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: dependencyIcon(dependency))
                        .font(.system(size: 18))
                        .foregroundColor(dependencyColor(dependency))
                }
                
                // Path
                VStack(alignment: .leading, spacing: 4) {
                    Text(dependency)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    
                    Text(dependencyType(dependency))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Edit icon
                Image(systemName: "pencil.circle.fill")
                    .font(.title3)
                    .foregroundColor(.accentColor)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
    
    private func dependencyIcon(_ dep: String) -> String {
        if dep.contains("CydiaSubstrate") || dep.contains("ElleKit") {
            return "cube.box.fill"
        } else if dep.contains(".framework") {
            return "shippingbox.fill"
        } else if dep.contains("@rpath") || dep.contains("@executable_path") {
            return "link.circle.fill"
        } else if dep.hasPrefix("/usr/lib") || dep.hasPrefix("/System") {
            return "gearshape.fill"
        } else {
            return "doc.fill"
        }
    }
    
    private func dependencyColor(_ dep: String) -> Color {
        if dep.contains("CydiaSubstrate") || dep.contains("ElleKit") {
            return .orange
        } else if dep.contains(".framework") {
            return .accentColor
        } else if dep.contains("@rpath") || dep.contains("@executable_path") {
            return .purple
        } else {
            return .gray
        }
    }
    
    private func dependencyType(_ dep: String) -> String {
        if dep.contains("CydiaSubstrate") {
            return "Tweak Substrate"
        } else if dep.contains("ElleKit") {
            return "Tweak Framework (ElleKit)"
        } else if dep.contains(".framework") {
            return "Framework"
        } else if dep.contains("@rpath") {
            return "Runtime Path"
        } else if dep.contains("@executable_path") {
            return "Executable Path"
        } else if dep.hasPrefix("/usr/lib") {
            return "System Library"
        } else if dep.hasPrefix("/System") {
            return "System Framework"
        } else {
            return "Dynamic Library"
        }
    }
}

// MARK: - ViewModel

@MainActor
class DependencyEditorViewModel: ObservableObject {
    @Published var dependencies: [String] = []
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage: String?
    @Published var showEditAlert = false
    @Published var selectedDependency: String?
    @Published var newPath: String = ""
    
    private let fileURL: URL
    private let editor: DylibDependencyEditor
    
    init(fileURL: URL) {
        self.fileURL = fileURL
        self.editor = DylibDependencyEditor(fileURL: fileURL)
        
        Task {
            await loadDependencies()
        }
    }
    
    func loadDependencies() async {
        isLoading = true
        
        await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            let deps = self.editor.getDependencies()
            
            await MainActor.run {
                self.dependencies = deps
                self.isLoading = false
            }
        }.value
    }
    
    func selectDependencyForEdit(_ dependency: String) {
        selectedDependency = dependency
        newPath = dependency
        showEditAlert = true
    }
    
    func replaceDependency() async {
        guard let oldPath = selectedDependency else { return }
        
        let newPathTrimmed = newPath.trimmingCharacters(in: .whitespaces)
        
        guard !newPathTrimmed.isEmpty else {
            showErrorMessage("New path cannot be empty")
            return
        }
        
        guard newPathTrimmed != oldPath else {
            // No change
            return
        }
        
        do {
            try editor.replaceDependency(old: oldPath, new: newPathTrimmed)
            
            // Reload dependencies
            await loadDependencies()
            
            
        } catch {
            showErrorMessage("Failed to replace dependency: \(error.localizedDescription)")
        }
        
        selectedDependency = nil
        newPath = ""
    }
    
    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
}
