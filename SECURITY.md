# Güvenlik Politikası

## Desteklenen sürümler

Yalnızca en son yayınlanan sürüm güvenlik düzeltmesi alır.

## Açık bildirme

Güvenlik açıklarını **herkese açık issue olarak açmayın**. Bunun yerine GitHub'ın
[özel güvenlik bildirimi](../../security/advisories/new) özelliğini kullanın.

Bildirime şunları ekleyin: etkilenen sürüm, yeniden üretme adımları ve olası etki.
Bildirimler 7 gün içinde yanıtlanır.

## Kapsam ve tasarım notları

- Nabız **ağ erişimi yapmaz**; hiçbir veri cihazdan çıkmaz.
- Uygulama sandbox dışında, kullanıcı yetkileriyle çalışır; yönetici (root) yetkisi istemez,
  ayrıcalıklı yardımcı (privileged helper) kurmaz.
- Tek harici süreç çağrısı, kullanıcı **Doğrulama** ekranında düğmeye bastığında çalıştırılan
  `/usr/bin/vm_stat`'tır (sabit yol, argümansız).
