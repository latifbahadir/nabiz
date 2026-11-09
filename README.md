# Nabız

macOS için menü çubuğunda yaşayan, **güvenilir** ve **neredeyse sıfır tüketimli** sistem izleyici.

Nabız, her değeri doğrudan macOS'un kendi kaynaklarından okur (Activity Monitor ve `top` ile aynı
kaynaklar) ve bunu kanıtlamak için uygulamanın içinde bir **Doğrulama** ekranı sunar: ham sayaçları,
hesaplama formülünü ve sistem araçlarıyla yan yana karşılaştırmayı gösterir.

## Özellikler

| Metrik | Kaynak | Durum |
|---|---|---|
| İşlemci (toplam, çekirdek başına, çekirdek tipine göre) | `host_processor_info` | ✅ v0.1 |
| Bellek (uygulama, sabit, sıkıştırılmış, önbellek, takas, baskı) | `host_statistics64`, `sysctl` | ✅ v0.1 |
| Ağ hızı (indirme / yükleme) | `sysctl NET_RT_IFLIST2` (64 bit sayaçlar) | ✅ v0.2 |
| Disk doluluğu ve okuma/yazma hızı | `URLResourceValues`, IOKit `IOBlockStorageDriver` | ✅ v0.2 |
| Pil (yüzde, kalan süre, sağlık, döngü, güç, sıcaklık) | `IOPowerSources`, IOKit `AppleSmartBattery` | ✅ v0.2 |
| GPU, sıcaklık, fan | IOKit / SMC (resmi olmayan) | 🗓 v0.3 |

Yol haritası ve görevler: [Issues](../../issues) ve [Milestones](../../milestones).

## İlkeler

1. **Doğruluk kanıtlanabilir olmalı.** Her metrik için kaynak, formül ve karşılaştırma komutu uygulamada görünür.
2. **Ölçen, ölçtüğünü bozmamalı.** Panel kapalıyken hedef: tek çekirdeğin %0,3'ünden az CPU, boşta ek uyanma yok.
3. **Gizlilik.** Nabız ağa hiçbir veri göndermez; telemetri, analiz ya da güncelleme denetimi yoktur.

Ayrıntılar: [docs/PRODUCT.md](docs/PRODUCT.md) · [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

## Gereksinimler

- macOS 14 (Sonoma) veya üstü, Apple Silicon
- Derlemek için Xcode 16+ (Swift 6 araç zinciri)

## Derleme ve çalıştırma

```bash
./scripts/build-app.sh          # build/Nabız.app oluşturur (ad-hoc imzalı)
open "build/Nabız.app"
```

Uygulamalar klasörüne kurmak için:

```bash
./scripts/build-app.sh && ditto "build/Nabız.app" "/Applications/Nabız.app"
```

> Menü çubuğu çok doluysa (özellikle çentikli ekranlarda) yeni öğeler çentiğin arkasında kalabilir.
> ⌘ tuşuna basılı tutup diğer öğeleri sürükleyerek yer açabilirsiniz.

## Test ve ölçüm

```bash
swift test                       # birim + sistem testleri
./scripts/measure-self.sh 60     # Nabız'ın 60 sn'lik kendi CPU tüketimini ölçer, bütçeyi aşarsa hata verir
```

## Katkı

Süreç, dal (branch) adlandırma, commit kuralları ve PR akışı için [CONTRIBUTING.md](CONTRIBUTING.md).
Güvenlik bildirimi için [SECURITY.md](SECURITY.md).

## Lisans

[MIT](LICENSE)
