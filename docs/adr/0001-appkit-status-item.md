# ADR 0001: Menü çubuğu için SwiftUI `MenuBarExtra` yerine AppKit `NSStatusItem`

- Durum: Kabul edildi
- Tarih: 2026-11-09

## Bağlam

Nabız gün boyu çalışır; kendi tüketimi ürünün temel ölçütlerinden biridir. Menü çubuğu öğesi 2 saniyede
bir güncellenir, panel ise nadiren açılır.

## Karar

Menü çubuğu öğesi `NSStatusItem`, panel `NSPopover` + `NSHostingController` ile yapılır. Panel
kapandığında `contentViewController` bırakılır; böylece kapalıyken hiçbir SwiftUI görünümü,
gözlem veya çizim maliyeti kalmaz. Panel açıldığında yeniden oluşturulur.

## Sonuçlar

- Açılış/kapanış olayları net (`NSPopoverDelegate`), veri yayını yalnızca panel açıkken yapılır.
- Menü çubuğu görüntüsü üzerinde tam denetim (iki satırlı, dar, şablon görüntü).
- Biraz daha fazla AppKit kodu gerekir.
