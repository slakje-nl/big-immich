import SwiftUI

/// A control on the Siri Remote that the Controls page can describe and highlight. Focusing its row
/// in the list lights up the matching element on the remote graphic.
enum RemoteControl: Hashable {
    case up, down, left, right, back, playPause

    var icon: String {
        switch self {
        case .up: "chevron.up"
        case .down: "chevron.down"
        case .left: "chevron.left"
        case .right: "chevron.right"
        case .back: "chevron.backward"
        case .playPause: "playpause.fill"
        }
    }
}

/// A stylised Siri Remote graphic for the Controls settings page — a tall remote body with the
/// click-pad and the two columns of hardware buttons (back / play-pause / mute on the left, TV and
/// the volume rocker on the right). It fills the height it's given. `highlight` emphasises one
/// control so it stays in sync with whatever row is focused in the list beside it.
struct RemoteDiagramView: View {
    var highlight: RemoteControl?

    var body: some View {
        VStack(spacing: 44) {
            clickpad
            buttonGrid
            Spacer(minLength: 0)
        }
        .padding(.vertical, 48)
        .padding(.horizontal, 30)
        .frame(width: 210)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.16), Color.white.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 44, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        )
        .animation(.easeInOut(duration: 0.15), value: highlight)
    }

    private var clickpad: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.35))
            Circle().stroke(Color.white.opacity(0.18), lineWidth: 1)

            VStack {
                padGlyph(.up)
                Spacer()
                padGlyph(.down)
            }
            .padding(18)

            HStack {
                padGlyph(.left)
                Spacer()
                padGlyph(.right)
            }
            .padding(18)

            Circle().fill(Color.white.opacity(0.06)).frame(width: 58, height: 58)
        }
        .frame(width: 142, height: 142)
        .font(.system(size: 16, weight: .bold))
    }

    private func padGlyph(_ control: RemoteControl) -> some View {
        let active = highlight == control
        return Image(systemName: control.icon)
            .foregroundColor(active ? .white : .white.opacity(0.5))
            .scaleEffect(active ? 1.4 : 1)
            .shadow(color: active ? .white.opacity(0.8) : .clear, radius: active ? 8 : 0)
    }

    private var buttonGrid: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(spacing: 22) {
                circleButton("chevron.backward", control: .back)
                circleButton("playpause.fill", control: .playPause)
                circleButton("speaker.slash.fill")
            }
            VStack(spacing: 22) {
                circleButton("tv")
                volumeButton
            }
        }
    }

    private func circleButton(_ icon: String, control: RemoteControl? = nil) -> some View {
        let active = control != nil && highlight == control
        let relevant = control != nil
        return Image(systemName: icon)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(active ? .white : .white.opacity(relevant ? 0.85 : 0.5))
            .frame(width: 56, height: 56)
            .background(Circle().fill(Color.white.opacity(active ? 0.3 : (relevant ? 0.14 : 0.07))))
            .overlay(active ? Circle().stroke(Color.white, lineWidth: 2) : nil)
            .scaleEffect(active ? 1.1 : 1)
            .shadow(color: active ? .white.opacity(0.6) : .clear, radius: active ? 10 : 0)
    }

    private var volumeButton: some View {
        VStack {
            Image(systemName: "plus")
            Spacer()
            Image(systemName: "minus")
        }
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(.white.opacity(0.5))
        .padding(.vertical, 16)
        .frame(width: 56, height: 134)
        .background(Capsule().fill(Color.white.opacity(0.07)))
    }
}
