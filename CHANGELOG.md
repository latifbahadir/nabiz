# Değişiklik Günlüğü

Biçim [Keep a Changelog](https://keepachangelog.com/tr-TR/1.1.0/), sürümleme
[Semantic Versioning](https://semver.org/lang/tr/) kurallarına uyar.

## [Yayınlanmamış]

### Eklendi
- Resmi olmayan API'ler için ortak izolasyon katmanı (`NabizUnofficial`): çalışma zamanında sembol çözümü,
  CF tip denetimi, ilk çağrıda çökme koruması ve tüm kaynakları kapatma anahtarı
  (`defaults write com.latifbahadir.nabiz DisableUnofficialAPIs -bool YES`) (#24).
- ADR 0003: resmi olmayan API kullanım kararı ve riskleri (#24).
- GPU: kullanım (`IOAccelerator` → `Device Utilization %`), işleyici/döşeyici oranları, GPU belleği ve geçmiş grafiği;
  Doğrulama ekranında ham sözlük, kaynak durumu ve `ioreg`/`powermetrics` karşılaştırması (#6).
- Sıcaklık: CPU (`Tp*`) ve GPU (`Tg*`) ortalama / en yüksek, SMC'den; yalnızca panel açıkken, sıklık seçilebilir
  (5 / 15 / 60 sn, varsayılan 60). Doğrulama ekranında tüm SMC sıcaklık anahtarları ve düğmeyle HID çapraz kontrolü (#7).
- Fan: her fan için anlık devir ve en yüksek devre oranı, SMC'den (yalnızca okuma); sıcaklıkla aynı sıklıkta,
  yalnızca panel açıkken. Fansız Mac'lerde bölüm gizlenir. Doğrulama ekranında ham `FNum`/`F*Ac`/`Tg`/`Mn`/`Mx` (#8).
- Uygulamalar sekmesi: CPU, bellek, GPU, enerji ve disk G/Ç'yi **kimin** kullandığı; işlemler uygulamaya göre
  gruplanır (ör. Chrome yardımcıları → Google Chrome), satır açılınca işlemler görünür; tür etiketi
  (Uygulama / Arka plan uygulaması / Sistem servisi / Diğer işlem). Kaynak: `proc_pid_rusage` (#30).
- Pili en çok harcayanlar: işlem enerji sayaçlarından uygulama başına enerji defteri (son 1 / 12 sa,
  yalnızca pildeyken filtresi); panel kapalıyken dakikada bir güncellenir. Pil ve Uygulamalar sekmelerinde (#30).
- Sistem sekmesinde CPU, GPU ve bellek için "En çok kullananlar" özeti; root işlemlerinin CPU payı toplamdan
  hesaplanıp ayrı gösterilir (#30).
- İşlem başına GPU süresi (`AGXDeviceUserClient` → `AppUsage`, resmi olmayan, `UnofficialGate` arkasında) (#30).

## [0.2.0] - 2026-11-09

### Eklendi
- Ağ: anlık indirme/yükleme hızı ve geçmiş grafiği; 64 bit arayüz sayaçları, VPN tünelleri çift sayılmaz (#2).
- Disk: doluluk (Finder ile aynı "kullanılabilir" tanımı), okuma/yazma hızı ve geçmiş grafiği (#3).
- Pil: yüzde, durum, kalan süre, sağlık, döngü sayısı, anlık güç ve sıcaklık (#4).
- Panel sekmeleri: Sistem, Ağ · Disk, Pil, Doğrulama.
- Doğrulama ekranına ağ, disk ve pil ham değerleri, formülleri ve karşılaştırma komutları.
- Girişte otomatik başlatma (`SMAppService`); /Applications dışından çalışırken ve onay gerektiğinde uyarı (#5).
- Geliştirme için `--login-item status|on|off` bayrağı.

### Değişti
- Süreç: issue'su olmayan geliştirme yapılmaz; dal adları issue numarası içerir (#16).
- Süreç: Dependabot PR'ları için issue otomatik açılır ve PR'a bağlanır (#18).
- `--snapshot` bayrağı artık sekme adı alır: `system`, `io`, `battery`, `verify`.

## [0.1.0] - 2026-11-09 (etiketlenmedi)

### Eklendi
- Menü çubuğunda iki satırlık CPU / RAM göstergesi ve açılır panel.
- İşlemci: toplam, kullanıcı/sistem ayrımı, çekirdek tipine göre (ör. Super / Performance) çekirdek başına yük, yük ortalaması.
- Bellek: uygulama, sabit, sıkıştırılmış, önbellek, takas ve bellek baskısı.
- Son 1 saatlik geçmiş grafikleri (5 dk / 15 dk / 1 sa).
- Doğrulama ekranı: Nabız'ın kendi tüketimi, ham CPU tick'leri ve formül, `vm_stat` ile yan yana karşılaştırma.
- Geliştirme için `--snapshot` bayrağı, `measure-self.sh` performans ölçüm betiği.

[Yayınlanmamış]: https://github.com/latifbahadir/nabiz/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/latifbahadir/nabiz/releases/tag/v0.2.0
[0.1.0]: https://github.com/latifbahadir/nabiz/commit/8289d3b
