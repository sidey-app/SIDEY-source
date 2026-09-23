import SwiftUI

struct CharacterSelectionGrid: View {
    let maximumColumns: Int
    let characters: [PixelCharacterDefinition]
    let confirmedSelection: String
    let pendingSelection: String?
    let isDisabled: Bool
    let onSelect: (String) -> Void

    init(
        maximumColumns: Int,
        characters: [PixelCharacterDefinition] = PixelCharacterCatalog.free,
        confirmedSelection: String,
        pendingSelection: String? = nil,
        isDisabled: Bool = false,
        onSelect: @escaping (String) -> Void
    ) {
        self.maximumColumns = maximumColumns
        self.characters = characters
        self.confirmedSelection = confirmedSelection
        self.pendingSelection = pendingSelection
        self.isDisabled = isDisabled
        self.onSelect = onSelect
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 92, maximum: 132), spacing: 12),
            count: maximumColumns
        )
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(characters) { character in
                CharacterSelectionCard(
                    character: character,
                    isSelected: PixelCharacterCatalog.canonicalID(for: confirmedSelection) == character.id,
                    isPending: pendingSelection.map {
                        PixelCharacterCatalog.canonicalID(for: $0) == character.id
                    } ?? false,
                    isDisabled: isDisabled,
                    onSelect: { onSelect(character.id) }
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("profile.character.selection.accessibility")
    }
}

private struct CharacterSelectionCard: View {
    let character: PixelCharacterDefinition
    let isSelected: Bool
    let isPending: Bool
    let isDisabled: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                Image(nsImage: PixelCharacterPreviewImage.image(for: character))
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
                Text(localizedName)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .modifier(ProfileSelectionAppearance(
                isSelected: isSelected,
                isPending: isPending
            ))
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(Text(localizedName))
        .accessibilityValue(Text(accessibilityValue))
    }

    private var localizedName: LocalizedStringResource {
        switch character.id {
        case "pixel_hamster": "character.pixel_hamster.name"
        case "pixel_cat": "character.pixel_cat.name"
        case "pixel_puppy": "character.pixel_puppy.name"
        case "pixel_rabbit": "character.pixel_rabbit.name"
        case "pixel_penguin": "character.pixel_penguin.name"
        case "pixel_guinea_pig": "character.pixel_guinea_pig.name"
        case "pixel_monkey": "character.pixel_monkey.name"
        case "pixel_chinchilla": "character.pixel_chinchilla.name"
        case "pixel_starlight_upalupa": "character.pixel_starlight_upalupa.name"
        case "pixel_otter": "character.pixel_otter.name"
        case "pixel_pig": "character.pixel_pig.name"
        case "pixel_tree": "character.pixel_tree.name"
        case "pixel_shiba": "character.pixel_shiba.name"
        case "pixel_duck": "character.pixel_duck.name"
        case "pixel_poop": "character.pixel_poop.name"
        case "pixel_tteokbokki": "character.pixel_tteokbokki.name"
        case "pixel_quokka": "character.pixel_quokka.name"
        default: "character.unknown.name"
        }
    }

    private var accessibilityValue: LocalizedStringResource {
        if isPending { return "profile.character.state.equipping" }
        return isSelected
            ? "profile.selection.state.selected"
            : "profile.selection.state.not_selected"
    }
}
