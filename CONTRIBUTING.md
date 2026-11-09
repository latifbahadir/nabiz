# Katkı Rehberi

Nabız'ın geliştirme süreci aşağıdaki adımlardan oluşur. Amaç: `main` her zaman çalışır durumda ve
yayınlanabilir olsun.

## Yaşam döngüsü

```
Fikir / hata ──► Issue (triage) ──► Planlama (milestone) ──► Dal ──► PR ──► CI + inceleme ──► Birleştirme ──► Sürüm
```

### 1. Issue — issue yoksa iş yok
- **Issue'su olmayan hiçbir kod, belge veya süreç değişikliği yapılmaz.** Küçük bir düzeltme bile önce issue olarak açılır.
- Bir sohbette, toplantıda veya PR incelemesinde alınan her karar da **önce issue'ya dönüştürülür**
  (karar, gerekçe, kabul kriterleri), geliştirme o issue üzerinden ilerler.
- Şablonları kullanın: **Hata bildirimi** veya **Özellik isteği**.
- Yeni issue'lar `ihtiyaç: triage` etiketiyle açılır. Bakımcı; tür, alan ve öncelik etiketlerini ekler,
  gerekiyorsa bir milestone'a bağlar.

#### Bağımlılık güncellemeleri (Dependabot)
Kuralın istisnası yoktur; Dependabot PR'ları da bir issue'ya bağlanır. Bu otomatik yapılır
(`.github/workflows/dependabot-issue.yml` → `scripts/dependabot-issue.sh`):
- Dependabot PR açınca `bakım` etiketli bir issue açılır ve PR açıklamasına `Closes #N` eklenir.
- PR birleşince issue tamamlandı, birleşmeden kapanırsa "planlanmadı" olarak kapanır.
- İş akışı `pull_request_target` ile çalışır ama PR'ın kodunu checkout etmez ve çalıştırmaz.

Birleştirme kararı yine bakımcıdadır; Dependabot PR'ları otomatik birleştirilmez.

### 2. Hazır tanımı (Definition of Ready)
Bir issue'ya başlanabilmesi için:
- Problem ve beklenen sonuç açık,
- **Kabul kriterleri** yazılı,
- Veri kaynağı (hangi API / sayaç) ve doğrulama yöntemi (hangi sistem aracıyla karşılaştırılacağı) belli.

### 3. Dal (branch)
`main`'e doğrudan commit **yapılamaz**; kural seti bunu herkes için (bakımcı dahil) engeller.

| Tür | Dal adı |
|---|---|
| Yeni özellik | `feat/<issue>-<kisa-ad>` |
| Hata düzeltme | `fix/<issue>-<kisa-ad>` |
| Belgeler | `docs/<issue>-<kisa-ad>` |
| Bakım / CI | `chore/<issue>-<kisa-ad>` |
| Performans | `perf/<issue>-<kisa-ad>` |

Örnek: `feat/5-giriste-baslat`. Dal adındaki numara, işin hangi issue'ya ait olduğunu gösterir.

### 4. Commit mesajları
[Conventional Commits](https://www.conventionalcommits.org/tr/) biçimi:

```
feat(ağ): anlık indirme/yükleme hızını ekle
fix(bellek): takas değerinin birimini düzelt
```

### 5. Pull request
- PR şablonundaki kontrol listesini doldurun ve ilgili issue'yu bağlayın (`Closes #12`).
  Bağlı issue'su olmayan PR birleştirilmez. Varsayılan: bir PR bir issue'yu kapatır.
- CI (`build-and-test`) yeşil olmalı.
- Tüm inceleme yorumları çözülmüş olmalı.
- **Yalnızca bakımcı (@latifbahadir) birleştirebilir.** Birleştirme yöntemi: *squash merge*; dal otomatik silinir.

### 6. Bitti tanımı (Definition of Done)
- Kabul kriterleri karşılandı,
- `swift test` geçiyor, yeni mantık için test eklendi,
- Yeni metrik varsa **Doğrulama** ekranında kaynağı, formülü ve karşılaştırma komutu var,
- `./scripts/measure-self.sh 60` performans bütçesini aşmıyor,
- `CHANGELOG.md` içindeki *Yayınlanmamış* bölümü güncellendi,
- Gerekirse README / docs güncellendi.

## Sürümleme ve yayın

- [Semantic Versioning](https://semver.org/lang/tr/): `MAJOR.MINOR.PATCH`.
- Her milestone bir küçük sürüme (MINOR) karşılık gelir (ör. `v0.2`).
- Yayın adımları (bakımcı):
  1. `CHANGELOG.md`'de *Yayınlanmamış* bölümünü yeni sürüm başlığına taşı, `Support/Info.plist` sürümünü artır (PR ile).
  2. PR birleşince `main` üzerinde etiket at: `git tag v0.2.0 && git push origin v0.2.0`.
  3. `release` iş akışı uygulamayı derler, zip'ler ve GitHub Release oluşturur.

## Yerel geliştirme

```bash
swift build                    # derle
swift test                     # test et
./scripts/build-app.sh         # .app paketini oluştur
./scripts/measure-self.sh 60   # kendi tüketimini ölç
build/Nabız.app/Contents/MacOS/Nabiz --snapshot /tmp/panel.png [system|io|battery|verify]   # paneli PNG'ye çiz
```

## Davranış kuralları

Bu projeye katılan herkes [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) kurallarına uyar.
