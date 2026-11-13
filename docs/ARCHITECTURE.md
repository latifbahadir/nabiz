# Mimari

## Genel akış

```
Timer (2 sn, %25 tolerans)
   │
   ▼
Monitor ── Samplers ── sistem çağrıları
   │        sürekli (her tik): CPU, Bellek, Ağ, Disk G/Ç, GPU   (~85 µs toplam)
   │        işlemler (proc_pid_rusage): panel açıkken her tik, kapalıyken 30 tikte bir (enerji defteri)
   │        yalnızca panel açıkken: İşlem başına GPU, Pil, Disk doluluğu (10 sn'de bir), birincil arayüz,
   │                                Sıcaklık ve fan (SMC, ayrı seri kuyrukta, varsayılan 60 sn'de bir)
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
| `Sources/NabizUnofficial/` | Resmi olmayan API'ler için izolasyon katmanı (ayrı hedef): `dlsym`, CF tip denetimi, `UnofficialGate`, çökme koruması |
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

### Resmi olmayan kaynaklar ([ADR 0003](adr/0003-resmi-olmayan-api-izolasyonu.md))

Belgelenmemiş anahtar veya özel sembol kullanan örnekleyiciler ayrıca:
1. Kaynağa yalnızca `NabizUnofficial` yardımcılarıyla erişir; özel semboller `PrivateSymbol.resolve` ile çözülür, bağlanmaz.
2. Değerleri `CFValue` ile tip denetleyerek okur; `as!` ve `!` kullanmaz.
3. Her okumayı kendi `UnofficialGate`'inin `call` bloğunda yapar ve sonucu `report` ile bildirir.
4. Kapının durumunu (`status`) Doğrulama ekranında gösterir.

## Düşük tüketim kararları

- Tek zamanlayıcı, toleranslı: macOS uyanmaları diğer işlerle birleştirebilir.
- Menü çubuğu öğesi bir şablon görüntüdür; yalnızca metin değişince yeniden oluşturulur.
- Panel kapalıyken SwiftUI'ye hiçbir değer yayınlanmaz ve görünüm ağacı yoktur.
- Grafikler en fazla 180 noktaya indirgenir.
- Pahalı çağrılar önbelleğe alınır: arayüz adları (`if_indextoname` içeride `getifaddrs` çağırır),
  disk sürücü listesi (30 tikte bir yenilenir).
- Birikimli sayaçlarda fark yalnızca iki okumada da bulunan anahtarlar için alınır; yeni takılan
  disk/arayüz hızda sıçrama yaratmaz, sıfırlanan sayaç negatif değer üretmez.

Karar gerekçeleri: [docs/adr](adr/).
