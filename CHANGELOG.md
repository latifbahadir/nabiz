# Değişiklik Günlüğü

Biçim [Keep a Changelog](https://keepachangelog.com/tr-TR/1.1.0/), sürümleme
[Semantic Versioning](https://semver.org/lang/tr/) kurallarına uyar.

## [Yayınlanmamış]

### Eklendi
- Ağ: anlık indirme/yükleme hızı ve geçmiş grafiği; 64 bit arayüz sayaçları, VPN tünelleri çift sayılmaz (#2).
- Disk: doluluk (Finder ile aynı "kullanılabilir" tanımı), okuma/yazma hızı ve geçmiş grafiği (#3).
- Pil: yüzde, durum, kalan süre, sağlık, döngü sayısı, anlık güç ve sıcaklık (#4).
- Panel sekmeleri: Sistem, Ağ · Disk, Pil, Doğrulama.
- Doğrulama ekranına ağ, disk ve pil ham değerleri, formülleri ve karşılaştırma komutları.

### Değişti
- Süreç: issue'su olmayan geliştirme yapılmaz; dal adları issue numarası içerir (#16).
- Süreç: Dependabot PR'ları için issue otomatik açılır ve PR'a bağlanır (#18).
- `--snapshot` bayrağı artık sekme adı alır: `system`, `io`, `battery`, `verify`.

## [0.1.0] - 2026-11-09

### Eklendi
- Menü çubuğunda iki satırlık CPU / RAM göstergesi ve açılır panel.
- İşlemci: toplam, kullanıcı/sistem ayrımı, çekirdek tipine göre (ör. Super / Performance) çekirdek başına yük, yük ortalaması.
- Bellek: uygulama, sabit, sıkıştırılmış, önbellek, takas ve bellek baskısı.
- Son 1 saatlik geçmiş grafikleri (5 dk / 15 dk / 1 sa).
- Doğrulama ekranı: Nabız'ın kendi tüketimi, ham CPU tick'leri ve formül, `vm_stat` ile yan yana karşılaştırma.
- Geliştirme için `--snapshot` bayrağı, `measure-self.sh` performans ölçüm betiği.

[Yayınlanmamış]: https://github.com/latifbahadir/nabiz/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/latifbahadir/nabiz/releases/tag/v0.1.0
