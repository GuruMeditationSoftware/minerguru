import Foundation
import Testing
@testable import MinerGuru

@Suite("Privacy mode")
struct PrivacyModeTests {
    @Test func scrambleIsStableAndKeepsShape() {
        let ip = "192.168.1.28"
        let scrambled = PrivacyMode.scramble(ip)
        #expect(scrambled == PrivacyMode.scramble(ip)) // no flicker
        #expect(scrambled != ip)
        #expect(scrambled.count == ip.count)
        #expect(scrambled.filter { $0 == "." }.count == 3)
        #expect(scrambled.allSatisfy { $0.isNumber || $0 == "." })
    }

    @Test func walletIsScrambledButWorkerStays() {
        let user = "bc1qc6xpuwkys8jsjt439tfw2eu3fctkx7ad0hkehe.worker1"
        let scrambled = PrivacyMode.scrambleStratumUser(user)
        #expect(scrambled.hasSuffix(".worker1"))
        #expect(!scrambled.hasPrefix("bc1qc6xp"))
        #expect(scrambled.count == user.count)
    }

    @Test func macStaysHexadecimal() {
        let scrambled = PrivacyMode.scramble("A4:CF:12:9B:00:7E", hex: true)
        #expect(scrambled != "A4:CF:12:9B:00:7E")
        #expect(scrambled.allSatisfy { $0 == ":" || $0.isHexDigit })
    }

    @Test func freeTextHidesAddressesOnly() {
        let line = "Connected to 192.168.1.33 as qruvqq2x9vyd9gykre058r4lda4gulpres33nr9aml.worker2 (mac a4:cf:12:9b:00:7e)"
        let scrambled = PrivacyMode.scrambleFreeText(line)
        #expect(scrambled.hasPrefix("Connected to "))
        #expect(!scrambled.contains("192.168.1.33"))
        #expect(!scrambled.contains("qruvqq2x9vyd9gykre058r4lda4gulpres33nr9aml"))
        #expect(scrambled.contains(".worker2 (mac "))
        #expect(!scrambled.contains("a4:cf:12:9b:00:7e"))
        #expect(PrivacyMode.scrambleFreeText("bitaxe-keller") == "bitaxe-keller") // normal names stay
    }

    @Test func redactorOnlyActsWhenActive() {
        #expect(Redactor(isActive: false).ip("10.0.0.1") == "10.0.0.1")
        #expect(Redactor(isActive: true).ip("10.0.0.1") != "10.0.0.1")
    }
}
