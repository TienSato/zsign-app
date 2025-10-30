//
//  HexEditorView.swift
//  zsignapp
//
//  Created by Sato on 26/10/25.
//

import SwiftUI

struct HexEditorView: View {
    let fileURL: URL
    
    @StateObject private var viewModel = HexEditorViewModel()
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab = 0 // 0 = Byte, 1 = String
    @State private var showSearchSheet = false
    @State private var showJumpSheet = false
    @State private var showSaveAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Tab selector (Byte | String)
                Picker("View Mode", selection: $selectedTab) {
                    Text("Byte").tag(0)
                    Text("String").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                Divider()
                
                // Content
                if viewModel.isLoading {
                    loadingView
                } else if viewModel.data.isEmpty {
                    emptyView
                } else {
                    hexContentView
                }
            }
            
            // Save confirmation overlay
            if viewModel.isSaving {
                savingOverlay
            }
        }
        .navigationTitle(fileURL.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            toolbarContent
        }
        .sheet(isPresented: $showSearchSheet) {
            searchSheet
        }
        .sheet(isPresented: $showJumpSheet) {
            jumpSheet
        }
        .alert("Save Changes", isPresented: $showSaveAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Save", role: .destructive) {
                Task {
                    await viewModel.saveChanges()
                }
            }
        } message: {
            Text("Do you want to save your changes to the file?")
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            Task {
                await viewModel.loadFile(fileURL)
            }
        }
        .onChange(of: viewModel.errorMessage) { error in
            if let error = error {
                errorMessage = error
                showErrorAlert = true
            }
        }
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button(action: {
                showJumpSheet = true
            }) {
                Image(systemName: "arrow.up.arrow.down")
            }
            .disabled(viewModel.data.isEmpty)
            
            Button(action: {
                showSearchSheet = true
            }) {
                Image(systemName: "magnifyingglass")
            }
            .disabled(viewModel.data.isEmpty)
            
            if viewModel.hasChanges {
                Button(action: {
                    showSaveAlert = true
                }) {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundColor(.blue)
                }
            }
        }
    }
    
    // MARK: - Content Views
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Loading file...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("Empty File")
                .font(.headline)
            
            Text("This file contains no data")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var hexContentView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(viewModel.displayRows, id: \.offset) { row in
                            if selectedTab == 0 {
                                // Byte view
                                ByteRowView(
                                    row: row,
                                    selectedOffset: viewModel.selectedOffset,
                                    searchResults: viewModel.searchResults,
                                    onByteSelected: { offset in
                                        viewModel.selectByte(at: offset)
                                    },
                                    onByteEdit: { offset, newValue in
                                        viewModel.editByte(at: offset, value: newValue)
                                    }
                                )
                                .id(row.offset)
                            } else {
                                // String view
                                StringRowView(
                                    row: row,
                                    selectedOffset: viewModel.selectedOffset,
                                    searchResults: viewModel.searchResults,
                                    onByteSelected: { offset in
                                        viewModel.selectByte(at: offset)
                                    }
                                )
                                .id(row.offset)
                            }
                        }
                    } header: {
                        headerView
                    }
                }
            }
            .onChange(of: viewModel.scrollToOffset) { offset in
                if let offset = offset {
                    withAnimation {
                        proxy.scrollTo(offset - (offset % 16), anchor: .center)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        viewModel.scrollToOffset = nil
                    }
                }
            }
        }
    }
    
    private var headerView: some View {
        HStack(spacing: 0) {
            // Offset header
            Text("Offset")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            
            if selectedTab == 0 {
                // Byte view headers
                Text("00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text("ASCII")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 150, alignment: .leading)
            } else {
                // String view header
                Text("String")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
    }
    
    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                
                Text("Saving changes...")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(radius: 10)
        }
    }
    
    // MARK: - Search Sheet
    
    private var searchSheet: some View {
        NavigationView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Search Hex Pattern")
                        .font(.headline)
                    
                    TextField("Enter hex (e.g., 4D5A or 4D 5A 90 00)", text: $viewModel.searchQuery)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.allCharacters)
                        .font(.system(.body, design: .monospaced))
                    
                    Text("Enter hex bytes separated by spaces (optional)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !viewModel.searchResults.isEmpty {
                        Text("Found \(viewModel.searchResults.count) result(s)")
                            .font(.caption)
                            .foregroundColor(.green)
                            .fontWeight(.medium)
                    } else if viewModel.searchQuery.count >= 2 && viewModel.searchCompleted {
                        Text("No results found")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding()
                
                if !viewModel.searchResults.isEmpty {
                    List {
                        ForEach(Array(viewModel.searchResults.enumerated()), id: \.offset) { index, offset in
                            Button {
                                viewModel.jumpToOffset(offset)
                                showSearchSheet = false
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Result #\(index + 1)")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        
                                        if #available(iOS 16.1, *) {
                                            Text("Offset: 0x\(String(format: "%08X", offset))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .fontDesign(.monospaced)
                                        } else {
                                            // Fallback on earlier versions
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "arrow.right.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                } else {
                    Spacer()
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showSearchSheet = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Search") {
                        viewModel.performSearch()
                    }
                    .disabled(viewModel.searchQuery.isEmpty)
                }
            }
        }
    }
    
    // MARK: - Jump Sheet
    
    private var jumpSheet: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Jump to Offset")
                        .font(.headline)
                    
                    TextField("Enter offset (hex or decimal)", text: $viewModel.jumpQuery)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.allCharacters)
                        .font(.system(.body, design: .monospaced))
                    
                    Text("Examples: 0x1000 or 4096")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding()
                
                Spacer()
            }
            .navigationTitle("Jump to Offset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showJumpSheet = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Jump") {
                        if viewModel.performJump() {
                            showJumpSheet = false
                        }
                    }
                    .disabled(viewModel.jumpQuery.isEmpty)
                }
            }
        }
    }
}

// MARK: - Byte Row View

struct ByteRowView: View {
    let row: HexRow
    let selectedOffset: Int?
    let searchResults: Set<Int>
    let onByteSelected: (Int) -> Void
    let onByteEdit: (Int, UInt8) -> Void
    
    @State private var editingOffset: Int?
    @State private var editValue: String = ""
    @FocusState private var isEditing: Bool
    
    var body: some View {
        HStack(spacing: 0) {
            // Offset
            Text(String(format: "%08X", row.offset))
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundColor(.blue)
                .frame(width: 80, alignment: .leading)
            
            // Hex bytes
            HStack(spacing: 3) {
                ForEach(0..<16, id: \.self) { index in
                    if index < row.bytes.count {
                        let offset = row.offset + index
                        let byte = row.bytes[index]
                        
                        if editingOffset == offset {
                            TextField("", text: $editValue)
                                .font(.system(size: 13, weight: .regular, design: .monospaced))
                                .frame(width: 20)
                                .multilineTextAlignment(.center)
                                .textFieldStyle(.plain)
                                .background(Color.blue.opacity(0.3))
                                .cornerRadius(3)
                                .autocapitalization(.allCharacters)
                                .focused($isEditing)
                                .onSubmit {
                                    submitEdit(offset: offset)
                                }
                                .onAppear {
                                    isEditing = true
                                }
                        } else {
                            Text(String(format: "%02X", byte))
                                .font(.system(size: 13, weight: .regular, design: .monospaced))
                                .frame(width: 20)
                                .padding(.vertical, 2)
                                .background(backgroundColor(for: offset))
                                .foregroundColor(foregroundColor(for: offset))
                                .cornerRadius(3)
                                .onTapGesture {
                                    handleByteTap(offset: offset, byte: byte)
                                }
                        }
                    } else {
                        Text("  ")
                            .font(.system(size: 13, design: .monospaced))
                            .frame(width: 20)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // ASCII
            Text(row.ascii)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 150, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(uiColor: .systemBackground))
    }
    
    private func backgroundColor(for offset: Int) -> Color {
        if searchResults.contains(offset) {
            return Color.yellow.opacity(0.4)
        } else if selectedOffset == offset {
            return Color.blue.opacity(0.2)
        } else {
            return Color.clear
        }
    }
    
    private func foregroundColor(for offset: Int) -> Color {
        if searchResults.contains(offset) || selectedOffset == offset {
            return .primary
        } else {
            return .secondary
        }
    }
    
    private func handleByteTap(offset: Int, byte: UInt8) {
        if editingOffset == offset {
            editingOffset = nil
            editValue = ""
        } else {
            onByteSelected(offset)
            editingOffset = offset
            editValue = String(format: "%02X", byte)
        }
    }
    
    private func submitEdit(offset: Int) {
        guard let value = UInt8(editValue, radix: 16) else {
            editingOffset = nil
            editValue = ""
            return
        }
        
        onByteEdit(offset, value)
        editingOffset = nil
        editValue = ""
    }
}

// MARK: - String Row View

struct StringRowView: View {
    let row: HexRow
    let selectedOffset: Int?
    let searchResults: Set<Int>
    let onByteSelected: (Int) -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            // Offset
            Text(String(format: "%08X", row.offset))
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundColor(.blue)
                .frame(width: 80, alignment: .leading)
            
            // String representation
            HStack(spacing: 2) {
                ForEach(0..<row.bytes.count, id: \.self) { index in
                    let offset = row.offset + index
                    let byte = row.bytes[index]
                    let char = characterForByte(byte)
                    
                    Text(String(char))
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .frame(width: 15)
                        .padding(.vertical, 2)
                        .background(backgroundColor(for: offset))
                        .foregroundColor(foregroundColor(for: offset, byte: byte))
                        .cornerRadius(3)
                        .onTapGesture {
                            onByteSelected(offset)
                        }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(uiColor: .systemBackground))
    }
    
    private func characterForByte(_ byte: UInt8) -> Character {
        if byte >= 32 && byte <= 126 {
            return Character(UnicodeScalar(byte))
        } else {
            return "."
        }
    }
    
    private func backgroundColor(for offset: Int) -> Color {
        if searchResults.contains(offset) {
            return Color.yellow.opacity(0.4)
        } else if selectedOffset == offset {
            return Color.blue.opacity(0.2)
        } else {
            return Color.clear
        }
    }
    
    private func foregroundColor(for offset: Int, byte: UInt8) -> Color {
        if searchResults.contains(offset) || selectedOffset == offset {
            return .primary
        } else if byte >= 32 && byte <= 126 {
            return .primary
        } else {
            return .secondary
        }
    }
}

// MARK: - Hex Editor ViewModel

@MainActor
class HexEditorViewModel: ObservableObject {
    @Published var data: Data = Data()
    @Published var displayRows: [HexRow] = []
    @Published var selectedOffset: Int?
    @Published var searchQuery: String = ""
    @Published var searchResults: Set<Int> = []
    @Published var searchCompleted: Bool = false
    @Published var jumpQuery: String = ""
    @Published var scrollToOffset: Int?
    @Published var hasChanges: Bool = false
    @Published var isLoading: Bool = false
    @Published var isSaving: Bool = false
    @Published var errorMessage: String?
    
    private var fileURL: URL?
    private var originalData: Data = Data()
    
    func loadFile(_ url: URL) async {
        isLoading = true
        
        do {
            let data = try Data(contentsOf: url)
            
            await MainActor.run {
                self.fileURL = url
                self.data = data
                self.originalData = data
                self.hasChanges = false
                self.updateDisplayRows()
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load file: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    func updateDisplayRows() {
        var rows: [HexRow] = []
        let totalBytes = data.count
        
        for offset in stride(from: 0, to: totalBytes, by: 16) {
            let end = min(offset + 16, totalBytes)
            let bytes = Array(data[offset..<end])
            
            let ascii = bytes.map { byte -> Character in
                if byte >= 32 && byte <= 126 {
                    return Character(UnicodeScalar(byte))
                } else {
                    return "."
                }
            }
            
            rows.append(HexRow(
                offset: offset,
                bytes: bytes,
                ascii: String(ascii)
            ))
        }
        
        displayRows = rows
    }
    
    func selectByte(at offset: Int) {
        selectedOffset = offset
    }
    
    func editByte(at offset: Int, value: UInt8) {
        guard offset < data.count else { return }
        
        data[offset] = value
        hasChanges = true
        updateDisplayRows()
    }
    
    func performSearch() {
        searchCompleted = false
        searchResults.removeAll()
        
        let cleaned = searchQuery.replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { return }
        
        var searchBytes: [UInt8] = []
        
        for i in stride(from: 0, to: cleaned.count, by: 2) {
            let start = cleaned.index(cleaned.startIndex, offsetBy: i)
            let end = cleaned.index(start, offsetBy: min(2, cleaned.count - i))
            let byteString = String(cleaned[start..<end])
            
            if let byte = UInt8(byteString, radix: 16) {
                searchBytes.append(byte)
            } else {
                return
            }
        }
        
        guard !searchBytes.isEmpty else { return }
        
        for offset in 0..<(data.count - searchBytes.count + 1) {
            var match = true
            for i in 0..<searchBytes.count {
                if data[offset + i] != searchBytes[i] {
                    match = false
                    break
                }
            }
            
            if match {
                for i in 0..<searchBytes.count {
                    searchResults.insert(offset + i)
                }
            }
        }
        
        searchCompleted = true
    }
    
    func performJump() -> Bool {
        let cleaned = jumpQuery.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return false }
        
        var offset: Int?
        
        if cleaned.hasPrefix("0x") || cleaned.hasPrefix("0X") {
            let hexString = String(cleaned.dropFirst(2))
            offset = Int(hexString, radix: 16)
        } else {
            offset = Int(cleaned)
        }
        
        guard let offset = offset, offset >= 0, offset < data.count else {
            errorMessage = "Invalid offset"
            return false
        }
        
        jumpToOffset(offset)
        return true
    }
    
    func jumpToOffset(_ offset: Int) {
        selectedOffset = offset
        scrollToOffset = offset
    }
    
    func saveChanges() async {
        guard let url = fileURL else { return }
        
        isSaving = true
        
        do {
            try data.write(to: url, options: .atomic)
            
            await MainActor.run {
                self.originalData = self.data
                self.hasChanges = false
                self.isSaving = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to save file: \(error.localizedDescription)"
                self.isSaving = false
            }
        }
    }
}

// MARK: - Hex Row Model

struct HexRow {
    let offset: Int
    let bytes: [UInt8]
    let ascii: String
}
