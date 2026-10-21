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
        XCTAssertEqual(LidSoundText.tabLine(situation(shown: 3, candidates: [])), "Nothing on the lid")
        XCTAssertEqual(LidSoundText.tabLine(situation(shown: 0, candidates: [])), "No sounds yet")
        XCTAssertEqual(LidSoundText.shelfLine(onLid: 3, of: 8), "3 of 8")
        XCTAssertEqual(LidSoundText.shelfLine(onLid: 8, of: 8), "All 8")
        XCTAssertEqual(LidSoundText.shelfLine(onLid: 0, of: 1), "0 of 1")
        XCTAssertEqual(LidSoundText.shelfLine(onLid: 0, of: 0), "Empty")
        XCTAssertEqual(LidSoundText.timingSummary(startDegrees: 60, withEffect: true, playsToEnd: false), "Starts at 60°, with the screen effect")
        XCTAssertEqual(LidSoundText.timingSummary(startDegrees: 45, withEffect: false, playsToEnd: true), "Starts at 45° · plays to the end")
        XCTAssertEqual(LidSoundText.timingSummary(startDegrees: nil, withEffect: false, playsToEnd: false), "Starts as the lid comes down")
        XCTAssertEqual(LidSoundText.bundledPacksLine(packs: ["Starters", "Pops", "Toys", "Machines", "Retro"], sounds: 75), "Starters, Pops, Toys and 2 more · 75 sounds")
        XCTAssertEqual(LidSoundText.bundledPacksLine(packs: ["Starters"], sounds: 3), "Starters · 3 sounds")
        var edges = situation(candidates: ["Rain"]); edges.capability = .lidStateOnly
        XCTAssertEqual(LidSoundText.tabLine(edges), "Rain · after the lid shuts")
    }

    func testTheHeadlineAlwaysAnswersWhatTheLidWillDo() {
        XCTAssertEqual(LidSoundText.copy(situation(on: false)).headline, "Closing the lid is silent.")
        XCTAssertEqual(LidSoundText.copy(situation(candidates: ["Rain"])).headline, "Closing the lid plays Rain.")
        XCTAssertEqual(LidSoundText.copy(situation(candidates: ["Rain"])).detail, "It starts as the lid comes down and ends as it lands.")
        var angled = situation(candidates: ["Rain"]); angled.startDegrees = 45
        XCTAssertEqual(LidSoundText.copy(angled).detail, "It starts as the lid passes 45° and ends as it lands.")
        angled.playsToEnd = true
        XCTAssertEqual(LidSoundText.copy(angled).detail, "It starts as the lid passes 45° and plays to the end; your Mac sleeps right after.")
        XCTAssertEqual(LidSoundText.partsFound(3), "3 parts, by the silence between them. Click one and drag the handles to fix it, × leaves one out; name them, then add.")
        XCTAssertEqual(LidSoundText.partsSuggested(5), "5 parts, by the silence between them: one sound each, in one go.")
        var pending = situation(); pending.sleepPendingSeconds = 7
        XCTAssertEqual(LidSoundText.tabLine(pending), "Still going to sleep")
        XCTAssertEqual(LidSoundText.copy(pending).headline, "Your Mac is still going to sleep from the last close.")
        XCTAssertEqual(LidSoundText.copy(pending).detail, "Closing the lid again does nothing until that finishes: 7 s so far. The sound still plays.")
        var slow = situation(candidates: ["Rain"]); slow.slowSleepers = ["Logitech G Hub"]
        XCTAssertEqual(LidSoundText.copy(slow).detail, "It starts as the lid comes down and ends as it lands.", "the card under the answer says it")
        XCTAssertTrue(LidSoundText.partsFound(1).hasPrefix("No silence to split at"))
        XCTAssertEqual(LidSoundText.copy(situation()).headline, "Closing the lid plays one of 3 sounds.")
        XCTAssertTrue(LidSoundText.copy(situation()).detail.hasSuffix("A different one each time."))
        var order = situation(mode: .inOrder); order.next = "Breath"
        XCTAssertEqual(LidSoundText.copy(order).headline, "Closing the lid plays 3 sounds in turn.")
        XCTAssertTrue(LidSoundText.copy(order).detail.hasSuffix("Next: Breath."))
        XCTAssertEqual(LidSoundText.copy(situation(muted: true)).headline, "Your Mac is muted, so closing is silent.")
        XCTAssertTrue(LidSoundText.copy(situation(whenMuted: .unmute, muted: true)).detail.contains("unmutes for the sound"))
        var noSwitch = situation(whenMuted: .unmute, muted: true); noSwitch.canUnmute = false
        XCTAssertTrue(LidSoundText.copy(noSwitch).detail.contains("no mute switch"))
        XCTAssertEqual(LidSoundText.copy(situation(shown: 3, candidates: [])).detail, "Nothing is on the lid. Drag a sound onto it from a pack, or press + beside one.")
        XCTAssertEqual(LidSoundText.copy(situation(shown: 0, candidates: [])).detail, "No sounds yet. Add one below.")
        var output = situation(candidates: ["Rain"]); output.outputName = "AirPods Pro"; output.onOpen = true
        XCTAssertEqual(LidSoundText.copy(output).detail,
                       "It starts as the lid comes down and ends as it lands. Through AirPods Pro.", "on open is said in Settings, not twice")
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
        XCTAssertEqual(LidSoundText.volumeAbout(.shareOfMac, macVolume: 0.06), "Of your Mac's volume (6 % now).")
        XCTAssertEqual(LidSoundText.volumeAbout(.ownLevel, macVolume: 0.06), "Your Mac is set to this for it, then put back.")
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
