import SwiftUI
import SwiftData

struct CategoriesSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var categories: [Category] = []
    @State private var showAddSheet = false
    @State private var showDeleteError = false
    @State private var deleteErrorText = ""

    var body: some View {
        List {
            ForEach(categories, id: \.id) { category in
                categoryRow(category)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(String(localized: "Categories"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(String(localized: "Add Category"))
            }
        }
        .onAppear { loadCategories() }
        .sheet(isPresented: $showAddSheet, onDismiss: loadCategories) {
            AddCategorySheet(onComplete: loadCategories)
        }
        .alert(String(localized: "Cannot Delete Category"), isPresented: $showDeleteError) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(deleteErrorText)
        }
    }

    private func categoryRow(_ category: Category) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: category.colorHex).opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: category.iconName)
                    .font(.subheadline)
                    .foregroundStyle(Color(hex: category.colorHex))
            }
            Text(category.name)
                .font(.body)
            Spacer()
            if category.isSystem {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !category.isSystem {
                Button(role: .destructive) {
                    deleteCategory(category)
                } label: {
                    Label(String(localized: "Delete"), systemImage: "trash")
                }
            }
        }
    }

    private func loadCategories() {
        do {
            categories = try CategoryRepository(context: modelContext).fetchAll()
        } catch {
            AppLogger.data.error("Failed to load categories: \(error)")
        }
    }

    private func deleteCategory(_ category: Category) {
        do {
            try CategoryRepository(context: modelContext).delete(category)
            loadCategories()
        } catch RepositoryError.cannotDeleteSystemCategory(let name) {
            deleteErrorText = String(localized: "'\(name)' is a built-in category and cannot be deleted.")
            showDeleteError = true
        } catch {
            deleteErrorText = error.localizedDescription
            showDeleteError = true
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        CategoriesSettingsView()
    }
    .modelContainer(PreviewContainer.shared)
}
#endif
