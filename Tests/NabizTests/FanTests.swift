import Foundation
import Testing
@testable import Nabiz
@testable import NabizUnofficial

@Suite("Fan")
struct FanTests {
    @Test("Oran = anlık / en yüksek, 0…1 ile sınırlı")
    func fraction() {
        #expect(FanInfo.fraction(actual: 1348, maximum: 5349).map { abs($0 - 1348.0 / 5349) < 1e-12 } == true)
        #expect(FanInfo.fraction(actual: 6000, maximum: 5349) == 1)
        #expect(FanInfo.fraction(actual: 0, maximum: 5349) == 0)
        #expect(FanInfo.fraction(actual: 1000, maximum: 0) == nil)
        #expect(FanInfo.fraction(actual: 1000, maximum: nil) == nil)
        #expect(FanInfo.fraction(actual: .nan, maximum: 5000) == nil)
    }

    @Test("Durmuş fan")
    func stopped() {
        #expect(FanInfo(id: 0, actual: 0, target: 0, minimum: 1350, maximum: 5349).isStopped)
        #expect(!FanInfo(id: 0, actual: 1350, target: 1350, minimum: 1350, maximum: 5349).isStopped)
    }

    @Test("Anahtar adları fan numarasını içerir")
    func keys() {
        let keys = FanReader.keys(forFan: 1)
        #expect([keys.actual, keys.target, keys.minimum, keys.maximum] == ["F1Ac", "F1Tg", "F1Mn", "F1Mx"])
        #expect(FourCC(keys.actual) != nil)
    }

    @Test("Gerçek sistem: SMC varsa fanlar tutarlı (fansız Mac'te liste boş)")
    func realSystem() throws {
        guard let client = try? SMCClient() else { return } // CI sanal makinesi
        let snapshot = try FanReader.read(client)
        #expect(snapshot.fans.count == snapshot.count)
        for fan in snapshot.fans {
            #expect(fan.actual >= 0 && fan.actual < 20_000)
            if let minimum = fan.minimum, let maximum = fan.maximum { #expect(minimum <= maximum) }
        }
        #expect(snapshot.readings.first?.key == "FNum" || snapshot.count == 0)
    }
}
