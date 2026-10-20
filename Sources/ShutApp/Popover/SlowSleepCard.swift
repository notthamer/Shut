import SwiftUI
import Tuner

/// After a sleep that took long: who held it up, and what that does to the lid. Saffron,
/// like every warning, with an × that removes it until the next slow sleep.
struct SlowSleepCard: View {
    let slow: SleepWatch.SlowSleep
    let dismiss: () -> Void
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("▲").font(.system(size: 11)).foregroundStyle(theme.ink).frame(width: 20).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(AwakeText.slowSleepTitle(seconds: slow.seconds)).font(TunerTheme.bodyMedium).foregroundStyle(theme.ink)
                Text(AwakeText.slowSleepDetail(names: slow.names, seconds: slow.seconds))
                    .font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            IconButton("xmark", help: "Remove this note. It comes back after the next slow sleep.", action: dismiss)
                .accessibilityLabel("Remove the note about the slow sleep")
                .padding(.top, -4).padding(.trailing, -6)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(theme.washSaffron)
        .surface(.card, radius: TunerTheme.cardRadius)
        .clipShape(RoundedRectangle(cornerRadius: TunerTheme.cardRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
