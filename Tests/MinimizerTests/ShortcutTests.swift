import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Minimizer

final class ShortcutTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "hotkey.keyCode")
        UserDefaults.standard.removeObject(forKey: "hotkey.carbonModifiers")
        UserDefaults.standard.removeObject(forKey: "hotkey.display")
        super.tearDown()
    }

    func testShortcutStoreReturnsDefaultWhenNoShortcutWasSaved() {
        UserDefaults.standard.removeObject(forKey: "hotkey.keyCode")
        UserDefaults.standard.removeObject(forKey: "hotkey.carbonModifiers")
        UserDefaults.standard.removeObject(forKey: "hotkey.display")

        XCTAssertEqual(ShortcutStore.load(), Shortcut.default)
    }

    func testShortcutStoreRoundTripsSavedShortcut() {
        let shortcut = Shortcut(
            keyCode: UInt32(kVK_ANSI_D),
            carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
            display: "Control Option Command D"
        )

        ShortcutStore.save(shortcut)

        XCTAssertEqual(ShortcutStore.load(), shortcut)
    }

    func testShortcutTranslatorConvertsModifierFlagsToCarbonMask() {
        let mask = ShortcutTranslator.carbonModifiers(from: [.control, .option, .command])

        XCTAssertEqual(mask, UInt32(controlKey | optionKey | cmdKey))
    }

    func testShortcutTranslatorCreatesReadableKeyLabels() {
        XCTAssertEqual(ShortcutTranslator.keyLabel(keyCode: UInt16(kVK_Space), characters: nil), "Space")
        XCTAssertEqual(ShortcutTranslator.keyLabel(keyCode: UInt16(kVK_ANSI_M), characters: "m"), "M")
        XCTAssertEqual(ShortcutTranslator.keyLabel(keyCode: 999, characters: nil), "Key 999")
    }
}
