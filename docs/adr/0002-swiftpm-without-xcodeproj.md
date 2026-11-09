# ADR 0002: Xcode projesi yerine Swift Package + paketleme betiği

- Durum: Kabul edildi
- Tarih: 2026-11-09

## Bağlam

Proje tek bir menü çubuğu uygulamasıdır; asset kataloğu, entitlements veya uzantı (extension) gerektirmez.
`.xcodeproj` dosyaları büyük ve birleştirme çakışmalarına açıktır.

## Karar

Kod bir Swift Package'tır (`Package.swift`). `.app` paketi `scripts/build-app.sh` ile oluşturulur:
release derlemesi + `Support/Info.plist` + ad-hoc imza. Testler `swift test` ile çalışır.

## Sonuçlar

- Okunabilir, küçük ve CI'da kolay çalışan bir yapı.
- Xcode ile açmak için `Package.swift` doğrudan açılabilir.
- İleride ikon, entitlements veya notarize gerektiğinde betik genişletilir ya da bu karar yeniden değerlendirilir.
