import XCTest
@testable import ShutApp

/// The words of Lid sound, read as copy.
final class LidSoundTextTests: XCTestCase {
    private func situation(on: Bool = true, shown: Int = 3, candidates: [String] = ["Rain", "Breath", "Hum"],
                           mode: LidSoundSettings.Mode = .random, whenMuted: LidSoundSettings.WhenMuted = .stayQuiet,
                           muted: Bool = false) -> LidSoundText.Situation {
        LidSoundText.Situation(isOn: on, shownCount: shown, candidates: candidates, mode: mode, whenMuted: whenMuted, muted: muted)
    }

    func testTheTabSaysWhatLidSoundIsDoing() {
        XCTAssertEqual(LidSoundText.tabLine(situation(on: false)), "Off")
        XCTAssertEqual(LidSoundText.tabLine(situation(candidates: ["Rain"])), "Rain · On")
        XCTAssertEqual(LidSoundText.tabLine(situation()), "3 sounds · random")
        XCTAssertEqual(LidSoundText.tabLine(situation(mode: .inOrder)), "3 sounds · in order")
        XCTAssertEqual(LidSoundText.tabLine(situation(muted: true)), "Muted")
        XCTAssertEqual(LidSoundText.tabLine(situation(whenMuted: .unmute, muted: true)), "3 sounds · random", "it will unmute for it")
        var playing = situation(); playing.playing = "Rain"
        XCTAssertEqual(LidSoundText.tabLine(playing), "Playing Rain…")
        XCTAssertEqual(LidSoundText.tabLine(situation(shown: 3, candidates: [])), "No sound chosen")
        XCTAssertEqual(LidSoundText.tabLine(situation(shown: 0, candidates: [])), "No sounds yet")
        var edges = situation(candidates: ["Rain"]); edges.capability = .lidStateOnly
        XCTAssertEqual(LidSoundText.tabLine(edges), "Rain · after the lid shuts")
    }

    func testTheHeadlineAlwaysAnswersWhatTheLidWillDo() {
        XCTAssertEqual(LidSoundText.copy(situation(on: false)).headline, "Closing the lid is silent.")
        XCTAssertEqual(LidSoundText.copy(situation(candidates: ["Rain"])).headline, "Closing the lid plays Rain.")
        XCTAssertEqual(LidSoundText.copy(situation(candidates: ["Rain"])).detail, "It starts as the lid comes down and ends as it lands.")
        var angled = situation(candidates: ["Rain"]); angled.startDegrees = 45
        XCTAssertEqual(LidSoundText.copy(angled).detail, "It starts as the lid passes 45° and ends as it lands.")
        XCTAssertEqual(LidSoundText.copy(situation()).headline, "Closing the lid plays one of 3 sounds.")
        XCTAssertTrue(LidSoundText.copy(situation()).detail.hasSuffix("A different one each time."))
        var order = situation(mode: .inOrder); order.next = "Breath"
        XCTAssertEqual(LidSoundText.copy(order).headline, "Closing the lid plays 3 sounds in turn.")
        XCTAssertTrue(LidSoundText.copy(order).detail.hasSuffix("Next: Breath."))
        XCTAssertEqual(LidSoundText.copy(situation(muted: true)).headline, "Your Mac is muted, so closing is silent.")
        XCTAssertTrue(LidSoundText.copy(situation(whenMuted: .unmute, muted: true)).detail.contains("unmutes for the sound"))
        var noSwitch = situation(whenMuted: .unmute, muted: true); noSwitch.canUnmute = false
        XCTAssertTrue(LidSoundText.copy(noSwitch).detail.contains("no mute switch"))
        XCTAssertEqual(LidSoundText.copy(situation(shown: 3, candidates: [])).detail, "No sound is switched on. Switch one on below.")
        XCTAssertEqual(LidSoundText.copy(situation(shown: 0, candidates: [])).detail, "No sounds yet. Add one below.")
        var output = situation(candidates: ["Rain"]); output.outputName = "AirPods Pro"; output.onOpen = true
        XCTAssertEqual(LidSoundText.copy(output).detail,
                       "It starts as the lid comes down and ends as it lands. Opening plays one too. Through AirPods Pro.")
    }

    func testSmallWords() {
        XCTAssertEqual(LidSoundText.durationText(2.44), "2.4 s")
        XCTAssertEqual(LidSoundText.durationText(0.06), "0.1 s")
        XCTAssertEqual(LidSoundText.durationText(12.3), "12 s")
        XCTAssertEqual(LidSoundText.settingsSummary(onOpen: false, whenMuted: .stayQuiet), "Silent on open · stays quiet when muted")
        XCTAssertEqual(LidSoundText.settingsSummary(onOpen: true, whenMuted: .unmute), "A sound on open too · unmutes for it")
        XCTAssertEqual(LidSoundText.settingsSummary(onOpen: false, whenMuted: .stayQuiet, volumeMode: .shareOfMac),
                       "Silent on open · stays quiet when muted · follows the Mac's volume")
        XCTAssertEqual(LidSoundText.settingsSummary(onOpen: false, whenMuted: .stayQuiet, volumeMode: .ownLevel),
                       "Silent on open · stays quiet when muted", "the default needs no mention")
        XCTAssertEqual(LidSoundText.volumeAbout(.shareOfMac, macVolume: 0.06), "Of your Mac's volume (6 % now). Let go to hear it.")
        XCTAssertTrue(LidSoundText.volumeAbout(.ownLevel, macVolume: 0.06).hasPrefix("Your Mac is set to this"))
        XCTAssertEqual(LidSoundText.refusal(.tooLong(900), name: "Album.m4a"), "Album.m4a is 15 min long. Sounds are 10 minutes at most.")
        XCTAssertEqual(LidSoundText.durationText(200), "3 min 20 s")
        XCTAssertEqual(LidSoundText.clockText(72), "1:12")
        XCTAssertEqual(LidSoundText.cutName(of: "Song", from: 3, to: 7.4), "Song · 0:03–0:07")
        XCTAssertEqual(LidSoundText.cutRefusal(.tooShort), "A part is half a second at least.")
        XCTAssertEqual(LidSoundText.longNote(name: "Song", seconds: 200), "Song is 3 min 20 s long: the lid plays up to 30 s of it, from where you choose (Clip, in its row).")
        XCTAssertEqual(LidSoundText.refusal(.unreadable, name: "Notes.txt"), "Shut could not read Notes.txt.")
        XCTAssertEqual(LidSoundText.refusal(.duplicate(of: UUID()), name: "Rain.wav", duplicateOf: "Rain"), "Rain is already in the list.")
    }
}
