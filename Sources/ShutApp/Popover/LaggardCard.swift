import SwiftUI
import Tuner

/// Before any sleep: a known laggard is running, and every lid close will wait 30 s for it.
/// Saffron, like every warning, with the one action that works (Login Items does not), and
/// an × for whoever wants it left alone. The slow-sleep card is the same news after the
/// fact; while this one shows, that one stays away.
struct LaggardCard: View {
    let laggards: [SleepWatch.Laggard]
    let stop: (SleepWatch.Laggard) -> Void
    let dismiss: () -> Void
    /// Title and the Stop links only: for the Stay awake band, which has a fixed height.
    var compact = false
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        let names = laggards.map(\.name)
        HStack(alignment: .top, spacing: 10) {
            Text("▲").font(.system(size: 11)).foregroundStyle(theme.ink).frame(width: 20).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(AwakeText.laggardTitle(names: names)).font(TunerTheme.bodyMedium).foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !compact {
                    Text(AwakeText.laggardShort(names: names))
                        .font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 12) {
                    ForEach(laggards) { laggard in
                        QuietButton("Stop \(laggard.short)") { stop(laggard) }
                            .help("Take \(laggard.name) out of launchd for this session and the next login, and quit it. No password. Opening the app brings it back.")
                    }
                }
                .padding(.top, 4).padding(.leading, -6)
            }
            Spacer(minLength: 4)
            IconButton("xmark", help: "Leave it alone. This note does not come back for it.", action: dismiss)
                .accessibilityLabel("Leave the note about the slow sleep alone")
                .padding(.top, -4).padding(.trailing, -6)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(theme.washSaffron)
        .help(AwakeText.laggardDetail(names: names))
        .surface(.card, radius: TunerTheme.cardRadius)
        .clipShape(RoundedRectangle(cornerRadius: TunerTheme.cardRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
