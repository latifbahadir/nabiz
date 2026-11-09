# Ürün Tanımı

## Problem

Mevcut menü çubuğu izleyicileri (ör. Stats) değerlerin nereden geldiğini ve nasıl hesaplandığını
göstermez; kullanıcı gördüğü sayıya güvenemez. Bazıları da ölçtükleri sistemi fark edilir ölçüde yorar.

## Vizyon

Değerlerine güvenilebilen, bunu kendi içinde kanıtlayan ve çalıştığı fark edilmeyen bir sistem izleyici.

## Hedef kullanıcı

Mac'inin kaynak kullanımını gün boyu göz ucuyla takip etmek isteyen, gerektiğinde ayrıntıya inen
geliştiriciler ve ileri düzey kullanıcılar.

## Ürün ilkeleri

| İlke | Anlamı | Ölçüt |
|---|---|---|
| Doğruluk | Her metrik resmi bir sistem kaynağından okunur | Sistem aracıyla fark: CPU ±2 puan, bellek sayfa sayıları ±%1 (eşzamanlı ölçümde) |
| Şeffaflık | Kaynak, formül ve karşılaştırma komutu uygulamada görünür | Her metrik için Doğrulama ekranında bölüm |
| Düşük tüketim | Ölçen, ölçtüğünü bozmaz | Panel kapalı: tek çekirdeğin < %0,3'ü, boşta ek uyanma ≈ 0, bellek (phys_footprint, Activity Monitor "Bellek" sütunu) < 30 MB |
| Gizlilik | Ağ erişimi yok, telemetri yok | Ağ API'si kullanılmaz (PR incelemesinde denetlenir) |
| Dayanıklılık | Resmi olmayan API'ler bozulursa uygulama çökmez | İlgili metrik "okunamadı" gösterir |

## Kapsam dışı

- İşlem (process) yöneticisi / öldürme özelliği
- Uzak izleme, bulut senkronizasyonu
- Uzun süreli (günler/haftalar) geçmiş kaydı — ileride ayrıca değerlendirilir
- Intel Mac desteği (öncelik değil)

## Yol haritası

| Sürüm | İçerik | Durum |
|---|---|---|
| v0.1 | İskelet, CPU, RAM, geçmiş, doğrulama ekranı | ✅ |
| v0.2 | Ağ, disk, pil; girişte otomatik başlatma | Planlandı |
| v0.3 | GPU, sıcaklık, fan (resmi olmayan API'ler, izole modül) | Planlandı |
| v0.4 | Ayarlar, pil modunda seyrek örnekleme, uygulama ikonu | Planlandı |
| v1.0 | Kararlı sürüm, imzalı ve notarize edilmiş dağıtım | — |

Ayrıntılı görevler GitHub Issues ve Milestones üzerinden takip edilir.

## Yayın kriterleri (her sürüm)

- Milestone'daki tüm issue'lar kapalı,
- CI yeşil, `measure-self.sh` bütçe içinde,
- Yeni metrikler sistem araçlarıyla elle doğrulandı,
- CHANGELOG güncel.
