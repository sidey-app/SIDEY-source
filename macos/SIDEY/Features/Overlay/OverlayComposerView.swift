import SwiftUI

struct OverlayComposerView: View {
    @Bindable var model: AppModel
    let onSend: (String) -> Void
    let onInputActivity: () -> Void
    let onTypingChanged: (Bool) -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 28, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("메시지 입력 닫기")
            .accessibilityIdentifier("sidey.composer-close")

            ZStack(alignment: .leading) {
                if model.draft.isEmpty {
                    Text("메시지를 입력해 주세요").foregroundStyle(.tertiary)
                }
                NativeMessageField(
                    text: $model.draft,
                    onInputActivity: onInputActivity,
                    onSubmit: send,
                    onCancel: onCancel,
                    onTextEdited: onTypingChanged
                )
            }
            .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 40)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(!MessageValidator.isValid(MessageValidator.normalized(model.draft)))
            .accessibilityLabel("메시지 전송")
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
