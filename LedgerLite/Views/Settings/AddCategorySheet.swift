import SwiftUI
import SwiftData

struct AddCategorySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let onComplete: () -> Void

    @State private var name = ""
    @State private var selectedIcon = "tag.fill"
    @State private var selectedColor = "#FF6B35"
    @State private var showError = false
    @State private var errorText = ""
    @FocusState private var nameFocused: Bool

    private let symbols: [String] = [
        "fork.knife", "cart.fill", "car.fill", "airplane", "house.fill", "heart.fill",
        "bag.fill", "doc.text.fill", "popcorn.fill", "repeat.circle.fill", "gamecontroller.fill", "music.note",
        "book.fill", "graduationcap.fill", "dumbbell.fill", "cross.fill", "pawprint.fill", "gift.fill",
        "phone.fill", "wifi", "bolt.fill", "drop.fill", "flame.fill", "leaf.fill",
        "creditcard.fill", "banknote.fill", "chart.bar.fill", "briefcase.fill", "wrench.fill", "hammer.fill",
        "camera.fill", "tv.fill", "desktopcomputer", "headphones", "printer.fill", "scanner",
        "bus.fill", "tram.fill", "ferry.fill", "bicycle", "figure.walk", "figure.run",
        "tag.fill", "star.fill", "flag.fill", "bell.fill", "bookmark.fill", "square.grid.2x2.fill",
    ]

    private let colors: [String] = [
        "#FF6B35", "#4ECDC4", "#45B7D1", "#96CEB4", "#F0A500", "#DDA0DD",
        "#98D8C8", "#F7DC6F", "#BB8FCE", "#BDC3C7", "#E74C3C", "#3498DB",
    ]

    // Adaptive grids fill the available width on any device size, in landscape,
    // and at large Dynamic Type without hard-coding a column count.
    private let iconColumns = [GridItem(.adaptive(minimum: 48), spacing: 12)]
    private let colorColumns = [GridItem(.adaptive(minimum: 44), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    previewRow
                    nameSection
                    iconSection
                    colorSection
                }
                .padding()
                .padding(.top, 8)
            }
            .navigationTitle(String(localized: "New Category"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        save()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear { nameFocused = true }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
        .alert(String(localized: "Cannot Save"), isPresented: $showError) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(errorText)
        }
    }

    // MARK: - Preview

    private var previewRow: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: selectedColor).opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: selectedIcon)
                    .font(.title2)
                    .foregroundStyle(Color(hex: selectedColor))
            }
            Text(name.isEmpty ? String(localized: "Category Name") : name)
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(name.isEmpty ? .tertiary : .primary)
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Name

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Name"))
                .font(.headline)
            TextField(String(localized: "e.g. Coffee"), text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .submitLabel(.done)
        }
    }

    // MARK: - Icon picker

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Icon"))
                .font(.headline)
            LazyVGrid(columns: iconColumns, spacing: 12) {
                ForEach(symbols, id: \.self) { symbol in
                    Button {
                        selectedIcon = symbol
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selectedIcon == symbol
                                      ? Color(hex: selectedColor).opacity(0.18)
                                      : Color(.tertiarySystemFill))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(
                                            selectedIcon == symbol ? Color(hex: selectedColor) : Color(.separator),
                                            lineWidth: selectedIcon == symbol ? 2 : 1
                                        )
                                )
                                .frame(height: 44)
                            Image(systemName: symbol)
                                .font(.body)
                                .foregroundStyle(selectedIcon == symbol ? Color(hex: selectedColor) : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(symbol)
                }
            }
        }
    }

    // MARK: - Color picker

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Color"))
                .font(.headline)
            LazyVGrid(columns: colorColumns, spacing: 12) {
                ForEach(colors, id: \.self) { hex in
                    Button {
                        selectedColor = hex
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 40, height: 40)
                            if selectedColor == hex {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(hex)
                }
            }
        }
    }

    // MARK: - Save

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            let all = try CategoryRepository(context: modelContext).fetchAll()
            let nextOrder = (all.map(\.sortOrder).max() ?? -1) + 1
            _ = try CategoryRepository(context: modelContext).add(
                name: trimmed,
                iconName: selectedIcon,
                colorHex: selectedColor,
                sortOrder: nextOrder
            )
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onComplete()
            dismiss()
        } catch RepositoryError.duplicateName(let n) {
            errorText = String(localized: "A category named '\(n)' already exists.")
            showError = true
        } catch {
            errorText = error.localizedDescription
            showError = true
            AppLogger.data.error("Add category failed: \(error)")
        }
    }
}

#if DEBUG
#Preview {
    AddCategorySheet(onComplete: {})
        .modelContainer(PreviewContainer.shared)
}
#endif
