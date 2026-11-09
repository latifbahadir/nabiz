# ADR 0003: Resmi olmayan API'lerin kullanımı ve izolasyonu

- Durum: Kabul edildi
- Tarih: 2026-11-09
- İlgili: #24 (bu karar), #6 GPU, #7 sıcaklık, #8 fan

## Bağlam

v0.3'te gösterilecek GPU kullanımı, sıcaklık ve fan hızı için Apple'ın belgelenmiş bir API'si yoktur.
Apple Silicon'da bu değerlerin bilinen kaynakları:

| Metrik | Kaynak | Niteliği |
|---|---|---|
| GPU kullanımı | IOKit `IOAccelerator` → `PerformanceStatistics` sözlüğü (`Device Utilization %` vb.) | Resmi IOKit çağrıları, **belgelenmemiş anahtarlar** |
| Sıcaklık | `AppleSMC` `Tp*` (CPU) / `Tg*` (GPU) `flt` anahtarları — #7'de güncellendi, aşağıya bakın | Resmi IOKit çağrıları, **belgelenmemiş anahtarlar** |
| Sıcaklık (çapraz kontrol) | `IOHIDEventSystemClient` (`IOHIDEventSystemClientCreate`, `…SetMatching`, `IOHIDServiceClientCopyEvent`, `IOHIDEventGetFloatValue`) | **Özel semboller** (başlık dosyası yok) |
| Fan | `AppleSMC` kullanıcı istemcisi (`IOServiceOpen` + `IOConnectCallStructMethod`, `FNum`/`F0Ac`/`F0Mn`/`F0Mx` anahtarları) | Resmi IOKit çağrıları, **belgelenmemiş yapı ve anahtarlar** |

Riskler:
1. **Kaybolma / değişme:** macOS güncellemesi anahtarı kaldırabilir, adını ya da tipini değiştirebilir.
2. **Bağlantı hatası:** Özel sembolü doğrudan bağlamak, sembol kalktığında uygulamanın açılışta çökmesine yol açar.
3. **Çökme:** Yanlış imzayla çağrılan özel işlev veya yanlış boyutlu SMC yapısı süreci çökertebilir; Swift bunu yakalayamaz.
   Nabız girişte başladığı için bu bir **çökme döngüsü** demektir.
4. **Yanlış değer:** Anahtar var ama anlamı değişmiş olabilir (ör. ölçek). Kullanıcının güvenini en çok bu bozar.
5. **Dağıtım:** Özel API kullanımı Mac App Store'a girişi engeller (hedefimiz değil; ADR 0002 doğrudan dağıtım).

## Karar

Bu metrikler gösterilir, ancak yalnızca ayrı bir SwiftPM hedefi olan **`NabizUnofficial`** üzerinden ve
aşağıdaki kurallarla:

1. **Çalışma zamanında çözüm:** Özel semboller `PrivateSymbol.resolve` (`dlopen` + `dlsym`) ile çözülür, hiçbiri
   bağlanmaz. Sembol yoksa özellik "okunamadı: … sembolü bulunamadı" olur.
2. **Tip denetimi:** Belgelenmemiş değerler `CFValue` ile `CFGetTypeID` denetlenerek okunur; zorla dönüştürme
   (`as!`, `!`) yoktur. Tip değişirse değer `nil`, arayüzde "—".
3. **Tek kapı:** Her kaynak bir `UnofficialGate` arkasındadır. Kapı:
   - kullanıcı tüm resmi olmayan kaynakları kapattıysa
     (`defaults write com.latifbahadir.nabiz DisableUnofficialAPIs -bool YES` ya da `NABIZ_DISABLE_UNOFFICIAL=1`)
     gövdeyi hiç çalıştırmaz;
   - **ilk çağrıyı çökme korumasıyla** yapar: çağrıdan önce `~/Library/Application Support/Nabiz/crash-guard/<kaynak>.inflight`
     yazılır, çağrı dönünce silinir. Süreç arada çökerse sonraki açılışta kaynak kapalı başlar ve Doğrulama ekranı
     nedenini gösterir. İşaret macOS derlemesini ve Nabız sürümünü taşır; biri değişince kaynak yeniden denenir.
4. **Şeffaflık:** Her kaynağın durumu (`kullanılabilir` / `okunamadı: neden`) ve ham değerleri Doğrulama ekranında
   gösterilir; kullanıcı değeri bir sistem aracıyla karşılaştırabilir (`ioreg`, `powermetrics`, Activity Monitor).
5. **Maliyet:** Sıcaklık ve fan yalnızca panel açıkken okunur (sıcaklık varsayılan 60 sn'de bir, değiştirilebilir). GPU, geçmiş grafiği için sürekli okunabilir; ancak
   yalnızca ölçülen maliyeti bütçeye sığarsa (#6'daki karar).
6. **Yalnızca okuma:** Fan denetimi, SMC'ye yazma (yazma komutu hiç gönderilmez) ve yönetici (root) yetkisi gerektiren hiçbir şey yapılmaz.

### Ek (#7, 2026-11-09): sıcaklık kaynağı HID yerine SMC

M5 Pro / macOS 26.6'da HID sıcaklık servisleri küme adı vermiyor (yalnızca `PMU tdie1…14` ×3, geçersiz
`PMU tdev*` ≈ −9201 °C, sabit `PMU tcal`) ve 77 servisi okumak ~97 ms sürüyor. SMC'de `Tp*` (23) ve `Tg*` (42)
anahtarları var; yük testinde CPU yükü `Tp`'yi, GPU yükü `Tg`'yi en çok yükseltti. Bu yüzden:
- Gösterilen CPU/GPU sıcaklıkları SMC `Tp*`/`Tg*` anahtarlarından (geçerli değerlerin ortalaması ve en yükseği).
- HID yalnızca Doğrulama ekranında, düğmeyle, bağımsız çapraz kontrol olarak okunur.
- Anahtar eşlemesi bir sonraki çipte değişebilir: `Tp*`/`Tg*` bulunamazsa bölüm "okunamadı" olur; yeni çipte
  eşleme aynı yük testiyle yeniden doğrulanır.
- SMC çağrıları ana iş parçacığında değil, kendi seri kuyruğunda yapılır (ilk anahtar taraması ~0,7 sn).
- SMC alışveriş yapısının düzeni (80 bayt) her açılışta denetlenir; tutmazsa hiçbir çağrı yapılmaz.

## Değerlendirilen alternatifler

- **`powermetrics` çalıştırmak:** Resmi bir araç ve doğruluk açısından referans, ama `sudo` ister ve kendisi
  belirgin CPU harcar. Yalnızca kullanıcının elle karşılaştırması için Doğrulama ekranında komut olarak önerilir.
- **Bu metrikleri hiç göstermemek:** En güvenlisi, ama ürünün v0.3 hedefinin dışına düşer; Stats'ın yerine geçmek
  için GPU ve sıcaklık beklenen özellikler.
- **Ayrı yardımcı süreç (XPC) içinde okumak:** Çökme ana uygulamayı etkilemezdi, ama ek süreç bellek ve uyanma
  bütçesine aykırı. Çökme işareti aynı riski (döngü) çok daha ucuza kapatıyor. Gerçek bir çökme görülürse yeniden
  değerlendirilir.

## Sonuçlar

- Resmi olmayan bir kaynak bozulduğunda en kötü durum: uygulama **bir kez** kapanır, sonraki açılışta o metrik
  "okunamadı" olur, diğer metrikler çalışmaya devam eder.
- Çökme koruması yalnızca **ilk** çağrıyı kapsar (her çağrıda diske yazmak bütçeye aykırı). Sonraki çağrılarda
  çökme olasılığı aynı kod yolu olduğu için düşük kabul edilir; görülürse koruma genişletilir.
- Her yeni macOS ana sürümünde (ve beta'larda) bu üç kaynak Doğrulama ekranından elle kontrol edilir.
- Yeni bir resmi olmayan kaynak eklemek bu ADR'deki kurallara uymayı gerektirir; uymayan PR birleştirilmez.
