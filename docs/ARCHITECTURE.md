# Mimari

## Genel akış

```
Timer (2 sn, %25 tolerans)
   │
   ▼
Monitor ── Samplers (CPU, Bellek, …) ── sistem çağrıları
   │  ├─ RingBuffer<HistoryPoint>   (son 1 saat, bellekte)
   │  ├─ onTick ──► StatusBarController ──► menü çubuğu görüntüsü (yalnızca değer değişince)
   │  └─ panel açıksa ──► PanelModel (@Observable) ──► SwiftUI panel
   ▼
Panel kapanınca SwiftUI görünüm ağacı tamamen bırakılır
```

## Dizinler

| Yol | İçerik |
|---|---|
| `Sources/Nabiz/App.swift` | Giriş noktası, `NSApplication` (Dock ikonu yok) |
| `Sources/Nabiz/Monitor.swift` | Zamanlayıcı, örnekleyicileri çağırma, geçmiş tamponu |
| `Sources/Nabiz/StatusBarController.swift` | `NSStatusItem` + `NSPopover` |
| `Sources/Nabiz/PanelModel.swift` | Panelin gözlenen durumu |
| `Sources/Nabiz/Samplers/` | Her metrik için bir örnekleyici; saf veri döndürür |
| `Sources/Nabiz/Views/` | SwiftUI görünümleri |
| `Tests/NabizTests/` | Swift Testing ile birim ve sistem testleri |
| `docs/adr/` | Mimari karar kayıtları |

## Örnekleyici sözleşmesi

Yeni bir metrik eklerken:
1. `Samplers/` altında `XSampler` sınıfı ve `XSnapshot` değer tipi (`Sendable`) yazılır.
2. Örnekleme ucuz olmalı (mikrosaniyeler); pahalı işler yalnızca panel açıkken yapılır.
3. Oran gerektiren metrikler (CPU, ağ, disk hızı) önceki okumayı saklar ve farktan hesaplar; ilk okuma `nil` döner.
4. Okunamayan değer uygulamayı çökertmez; `nil` döner ve arayüz "—" gösterir.
5. Doğrulama ekranına kaynak, formül ve karşılaştırma komutu eklenir.
6. Saf hesaplama mantığı için birim testi, gerçek sistem okuması için makullük testi yazılır.

## Düşük tüketim kararları

- Tek zamanlayıcı, toleranslı: macOS uyanmaları diğer işlerle birleştirebilir.
- Menü çubuğu öğesi bir şablon görüntüdür; yalnızca metin değişince yeniden oluşturulur.
- Panel kapalıyken SwiftUI'ye hiçbir değer yayınlanmaz ve görünüm ağacı yoktur.
- Grafikler en fazla 180 noktaya indirgenir.

Karar gerekçeleri: [docs/adr](adr/).
