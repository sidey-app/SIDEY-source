import SwiftUI

struct OverlayComposerView: View {
    @Bindable var model: AppModel
    let onSend: (String) -> Void
    let onInputActivity: () -> Void
    let onTypingChanged: (Bool) -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ComposerDragHandle().frame(width: 14, height: 34)
            ZStack(alignment: .leading) {
                if model.draft.isEmpty {
                    Text(L10n.text("message.composer.placeholder")).foregroundStyle(.tertiary)
                }
                NativeMessageField(
                    text: $model.draft,
                    onInputActivity: onInputActivity,
                    onSubmit: send,
                    onCancel: onCancel,
                    onTextEdited: onTypingChanged,
                    onFocusLost: { onTypingChanged(false) }
                )
            }
            .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 40)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(!model.canSubmitDraft)
            .accessibilityLabel(L10n.text("message.send.accessibility"))
        }
        .font(.system(size: 16, weight: .medium))
        .padding(.horizontal, 14)
        .frame(width: 390, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .glassEffect(in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .padding(5)
        .background(Color.clear)
    }

    private func send() {
        guard let body = model.acceptDraft() else { return }
        onTypingChanged(false)
        onSend(body)
    }
}
