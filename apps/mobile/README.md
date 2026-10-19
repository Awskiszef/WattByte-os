# WattByte mobile (Flutter)

Pokazuje, ile danych i energii zużywa Twój telefon: transfer komórkowy i Wi‑Fi,
sesje ładowania, mAh, Wh/kWh i szacowany koszt prądu. Wszystko liczone i
przechowywane lokalnie, działa offline.

## Zasada nr 1: bez fałszywych danych

| Wartość | Android | iOS |
|---|---|---|
| Transfer komórkowy / Wi‑Fi, download / upload, dzienna historia | **Zmierzone** – `NetworkStatsManager.querySummaryForDevice` (uprawnienie „Dostęp do danych o użyciu”) | **Szacowane** – liczniki interfejsów `getifaddrs` (`en0`, `pdp_ip*`) próbkowane, gdy aplikacja działa lub odświeża się w tle; przyrost rozkładany liniowo na dni |
| Dane wg aplikacji | **Zmierzone** – `NetworkStatsManager.querySummary` + `PackageManager` (widoczność przez `<queries>` launchera, bez `QUERY_ALL_PACKAGES`) | **Brak API → ekran ukryty** |
| Sesje ładowania (start/koniec, %) | **Zmierzone** – WorkManager z `setRequiresCharging(true)` próbkuje co 60 s | **Częściowo** – `UIDevice` tylko gdy aplikacja działa lub BGAppRefresh; sesje z rzadkich próbek oznaczane jako przybliżone |
| mAh dodane | **Zmierzone**, jeśli `BATTERY_PROPERTY_CHARGE_COUNTER`; inaczej szacowane | **Szacowane** – pojemność projektowa (baza urządzeń albo wpisana ręcznie) × Δ% |
| Pojemność baterii | **Projektowa** (nominalna pojemność modelu) z bazy urządzeń po `Build.MODEL` albo wpisana ręcznie; osobno **szacowana pojemność przy pełnym naładowaniu** tej baterii = `CHARGE_COUNTER` / (poziom / 100), od poziomu 40 %, zawsze z etykietą Szacowane i pewnością (high / medium / low). Licznik ładunku to ładunek *aktualnie* w baterii, nigdy pojemność nominalna | **Projektowa** z bazy po `utsname.machine` albo wpisana ręcznie; nieznany model = „Battery capacity unavailable”, bez „typowej” wartości. Brak szacowanej (brak publicznego licznika, bez prywatnych API) |
| Wh w baterii | **Zmierzone**, jeśli `BATTERY_PROPERTY_ENERGY_COUNTER`; inaczej mAh × V (V z `EXTRA_VOLTAGE` lub 3,85 V nominalnie) | **Szacowane** – mAh × 3,85 V |
| Energia z gniazdka, koszt | **Szacowane** – Wh / sprawność (domyślnie 85 %) × cena | j.w. |

Każda wartość szacowana ma w UI prefiks `~` i etykietę **Estimated / Szacowane**.
Nie używamy prywatnych API, roota ani jailbreaka. Różnica między pojemnością projektową a szacowaną: `../../docs/BATTERY_CAPACITY.md`.

Wzory (`lib/calc/energy.dart`):

```
Wh  = mAh × V / 1000
kWh = Wh / 1000
Wall Wh = Battery Wh / efficiency     (0 < efficiency ≤ 1)
cost = Wall kWh × price
```

## Struktura

```
packages/wattbyte_system/   plugin: oficjalne API systemowe (Kotlin / Swift) + typowany mostek Dart
lib/domain/                 wspólne modele (DailyData, BatterySample, ChargingSession, SessionEnergy); battery_capacity.dart: pojemność projektowa vs szacowana (czysty Dart)
lib/core/                   jednostki (MB/GB/TB, Wh/kWh, waluta), okresy kalendarzowe
lib/calc/                   matematyka energii (czyste funkcje)
lib/collection/             SessionBuilder (próbki → sesje), CounterFolder (iOS), Collector
lib/storage/                SQLite (sqflite): schemat, migracje, idempotentne zapisy
lib/sync/                   DailyAggregate, SyncQueueItem/SyncState, DeviceRegistration, CloudSyncSettings
lib/features/auth/          User, AuthSession, AuthState, AuthRepository, secure token store, Account screen
lib/analytics/              statystyki, rekordy, insights, reguły powiadomień, model dashboardu
lib/settings/               model ustawień + SharedPreferences (bez tokenów)
lib/export/                 CSV / JSON
lib/background/             pipeline odświeżania (UI + tło), widgety, powiadomienia, WorkManager/BGAppRefresh
lib/ui/                     ekrany, motyw, wykresy
lib/l10n/                   en + pl (ARB, gen-l10n)
lib/generated/api/          klient API generowany z OpenAPI (pnpm dart-client)
test/                       testy czystej logiki
```

Przepływ: `RefreshService.run()` → `Collector` (system → SQLite) → `DashboardModel` →
widgety (`home_widget`) → `SyncQueue` (agregaty dzienne, nic nie jest wysyłane) →
reguły powiadomień. Ten sam kod działa w UI (wznowienie, pull‑to‑refresh, timer
60 s) i w tle (`workmanager`).

## Konfiguracja backendu (`--dart-define`)

Każdy build WattByte potrzebuje backendu: adres API jest wkompilowany przez `--dart-define=API_BASE_URL=...`, a
normalny przepływ to zawsze

```
Launch → Welcome → Register / Login → Automatic Setup → Permissions → Dashboard
```

Build **bez** adresu API nie jest „aplikacją lokalną”, tylko **błędną konfiguracją**: nie przechodzi do
konfiguracji urządzenia z pominięciem konta. Jedyny sposób na uruchomienie bez backendu to jawny tryb
deweloperski `LOCAL_ONLY_DEV=true` i istnieje on **wyłącznie w buildzie debug**. Zwykłe `flutter run` bez
definów kończy się ekranem błędu konfiguracji. Całą decyzję podejmuje jedna czysta funkcja
`validateBackendConfig` (`lib/config/backend_config.dart`), używana przez `AppConfig`; żaden ekran nie sprawdza
`API_BASE_URL` samodzielnie. Pełny opis: [`../../README.md`](../../README.md) (sekcja „Configuration (mobile)”)
i [`../../docs/CONFIGURATION_MOBILE.md`](../../docs/CONFIGURATION_MOBILE.md).

| Define | Kiedy wymagany | Znaczenie |
|---|---|---|
| `API_BASE_URL` | zawsze, poza debug + `LOCAL_ONLY_DEV=true` | adres API (absolutny `http(s)`); w zestawach reguł `staging` i `production` (zob. `APP_ENV`) tylko `https` i bez hostów `.invalid` |
| `LOCAL_ONLY_DEV` | nigdy (domyślnie `false`) | `true` uruchamia build debug bez backendu i bez konta; inny zapis niż `true` / `false` jest błędem; `true` w buildzie profile lub release jest błędem, błędem jest też `true` razem z `APP_ENV=staging` lub `production` (albo literówką), nawet w buildzie debug |
| `APP_ENV` | opcjonalny | `development`, `staging`, `production`: zestaw reguł dla adresu (https, brak hostów `.invalid`). Brak definu oznacza `development` w buildzie **debug** i `production` w buildzie **profile lub release** (najostrzejszy zestaw: build, który trafia do ludzi, nie przyjmuje nieszyfrowanego HTTP tylko dlatego, że zapomniano o definie). Jawna wartość obowiązuje w każdym trybie; literówka (`prod`) liczy się jako `production` |
| `PRIVACY_POLICY_URL` | buildy sklepowe | publiczna strona https z polityką prywatności |

| Tryb buildu | `API_BASE_URL` | `LOCAL_ONLY_DEV` | Wynik |
|---|---|---|---|
| debug | poprawny | brak / `false` | **online**: pełny przepływ Flutter → API → konto |
| debug | brak | `true` | **local-only (development)**: bez konta, pasek `LOCAL ONLY DEVELOPMENT MODE` (tylko gdy `APP_ENV` brak lub `development`; przy `staging`, `production` albo literówce: błąd) |
| debug | brak | brak / `false` | **błąd**: ekran „Invalid build configuration” |
| debug | poprawny | `true` | **błąd**: ustawienia sobie przeczą |
| profile, release | poprawny | brak / `false` | **online** (walidowany jako `production`, chyba że `APP_ENV` mówi inaczej) |
| profile, release | brak | dowolna | **błąd**: build się nie kompiluje, `[WB-CONFIG-001]` |
| profile, release | dowolny | `true` | **błąd**: build się nie kompiluje, `[WB-CONFIG-002]` (gdy brakuje też adresu, strażnik wskazuje najpierw `[WB-CONFIG-001]`) |
| dowolny | podany, ale nie do użycia (zły format, host `.invalid`, `http` w regułach staging / production, dane logowania w adresie) | dowolna | **błąd**: ekran błędu przy starcie; zły adres nigdy nie oznacza „braku backendu” |

Buildy profile i release są chronione trzykrotnie.

1. **Kompilator Darta** odmawia kompilacji, gdy `API_BASE_URL` jest puste (`[WB-CONFIG-001]`) albo `LOCAL_ONLY_DEV` ma
   wartość inną niż brak lub dokładnie `false` (`[WB-CONFIG-002]`: w buildzie profile lub release `LOCAL_ONLY_DEV=true`
   to tryb wyłącznie debug, a zapis w rodzaju `TRUE` czy ` false` też się nie kompiluje: fail-closed, bo walidator
   uruchomieniowy obcina białe znaki, a stała czasu kompilacji nie potrafi). Stała kompilacji nie umie sparsować adresu
   URL, więc ta warstwa obejmuje tylko te dwa błędy.
2. **Kontrola przy starcie**: `main()` uruchamia pełną kontrolę, zanim otworzy pamięć, sesję lub przepływ konta.
   Waliduje dla trybu buildu, w którym binarka naprawdę działa: aplikacja poznaje swój tryb ze stałych
   `dart.vm.product` / `dart.vm.profile`, które można nadpisać z wiersza poleceń, więc binarka, która twierdzi, że jest
   „debug”, ale działa bez asercji (asercje działają tylko w buildach debug JIT i w `flutter test`, czyli to build
   profile lub release AOT), jest walidowana jako release.
3. **`tool/check_backend_config.dart`** (CI i workflow release) zanim build powstanie; odrzuca każdy define o nazwie
   `dart.vm.*`.

Sam strażnik czasu kompilacji nie widzi nadpisania `dart.vm.*`; kontrola przy starcie je widzi. Buildy debug są
sprawdzane tylko przy starcie, bo `flutter test` i `flutter analyze` kompilują się bez definów. Build, który mimo błędu
się skompiluje, pokazuje kontrolowany ekran „Invalid build configuration” (po angielsku, dla deweloperów; nigdy nie
drukuje adresu ani danych logowania) i się zatrzymuje. Dwie podpowiedzi na nim (komendy `flutter run`) pojawiają się
tylko wtedy, gdy w czasie działania `kBuildMode == BuildMode.debug`; komunikaty błędów samego walidatora, które
wspominają `LOCAL_ONLY_DEV`, są w każdej binarce.

### Development online

Zwykła praca. Najpierw uruchom API (zob. `../../README.md`, sekcja Backend), potem:

```bash
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8080       # symulator iOS
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080        # emulator Androida → API na komputerze
flutter run --dart-define=API_BASE_URL=http://<adres-lan>:8080     # prawdziwy telefon w tej samej sieci Wi‑Fi
flutter run --dart-define-from-file=config/development.json        # kopia config/development.example.json
```

- Definy: `API_BASE_URL` (zwykły `http` jest dozwolony, bo w buildzie debug brak `APP_ENV` oznacza `development`;
  ten sam adres w buildzie profile lub release byłby walidowany jako `production` i odrzucony). Nie ustawiaj
  `LOCAL_ONLY_DEV`.
- Start: Launch → Welcome → Register / Login → Automatic Setup → Permissions → Dashboard. Konto jest wymagane
  także w buildzie debug. Bez paska.
- Zła konfiguracja (brak adresu, zły adres, `LOCAL_ONLY_DEV=true` razem z adresem): ekran „Invalid build
  configuration” z listą złamanych reguł i dwiema komendami naprawiającymi. Nic się nie ładuje.

W emulatorze Androida `localhost` to sam emulator; `10.0.2.2` to jego alias dla komputera, na którym działa.

### Development local-only

Praca nad aplikacją bez żadnego backendu. **Tylko build debug.**

```bash
flutter run --dart-define=LOCAL_ONLY_DEV=true
flutter run --dart-define-from-file=config/local-only-dev.json     # kopia config/local-only-dev.example.json
```

- Definy: tylko `LOCAL_ONLY_DEV=true` (`APP_ENV`, jeśli podane, musi być `development`). **Nie** dodawaj
  `API_BASE_URL` (takie połączenie jest odrzucane).
- Start: bez Welcome i bez Register / Login: Automatic Setup → Permissions → Dashboard. Nie ma konta ani funkcji
  chmurowych, bo nie ma backendu. Nad każdym ekranem jest czerwony pasek **`LOCAL ONLY DEVELOPMENT MODE`**, ten sam
  tekst trafia do logu debug przy starcie. Pasek istnieje tylko w tym trybie i nie pojawia się w normalnym buildzie:
  jest budowany tylko przy `kBuildMode == BuildMode.debug` i walidacji jako local-only, a sam napis to stała pusta
  poza buildami debug, więc w binarkach profile i release go nie ma (`tool/check_release_guard.sh --builds` przeszukuje
  prawdziwą binarkę release). Pasek to wizualna pomoc dla dewelopera: VoiceOver i TalkBack go nie odczytują.
- Zła konfiguracja: `LOCAL_ONLY_DEV=false` albo brak definu bez adresu w buildzie debug daje ekran błędu, tak samo
  `LOCAL_ONLY_DEV=true` z `APP_ENV=staging` lub `production` (albo literówką); `--profile` i `--release` z
  `LOCAL_ONLY_DEV=true` się nie kompilują (`[WB-CONFIG-001]` bez adresu, `[WB-CONFIG-002]` z adresem).

### Staging

Build release przeciw API stagingowemu; adresy są w pliku ignorowanym przez Git, nie w kodzie.

```bash
cp config/staging.example.json config/staging.json        # wpisz prawdziwe hosty https
flutter build appbundle --dart-define-from-file=config/staging.json
flutter build ipa       --dart-define-from-file=config/staging.json
```

- Definy: `APP_ENV=staging`, `API_BASE_URL=https://…` (tylko https), opcjonalnie `PRIVACY_POLICY_URL`. Nigdy
  `LOCAL_ONLY_DEV`.
- Start: przepływ online jak wyżej, bez paska.
- Zła konfiguracja: brak `API_BASE_URL` → błąd kompilacji `[WB-CONFIG-001]`; `LOCAL_ONLY_DEV=true` → błąd kompilacji
  `[WB-CONFIG-002]`; adres `http` albo niezmieniony placeholder `.invalid` z pliku przykładowego kompiluje się, ale
  aplikacja zatrzymuje się na ekranie błędu.

### Production

```bash
cp config/production.example.json config/production.json    # prawdziwe hosty https i publiczny adres polityki prywatności
flutter build appbundle --release --dart-define-from-file=config/production.json --build-number=<n>
flutter build ipa       --release --dart-define-from-file=config/production.json
```

Podpisane buildy sklepowe robi ręczny workflow `release.yml` (`../../docs/CI.md`, `../../docs/RELEASE.md`); przed
analizą, testami i podpisem uruchamia on kontrolę konfiguracji (`tool/check_backend_config.dart`). Workflow przekazuje
tylko `API_BASE_URL` (wymaga `https://`). Bez `APP_ENV` build release jest walidowany jako `production`, więc kontrola
i aplikacja stosują reguły produkcyjne (tylko https, bez hostów `.invalid`) także do buildu z workflow.
`PRIVACY_POLICY_URL` nie jest przekazywane, więc build z workflow nie ma wkompilowanego adresu polityki prywatności;
build z nim to lokalny build z `config/production.json` (zob. `../../docs/CI.md`).

- Definy: `APP_ENV=production`, `API_BASE_URL=https://…`, `PRIVACY_POLICY_URL=https://…`. Nigdy `LOCAL_ONLY_DEV`.
- Start: Launch → Welcome → Register / Login → Automatic Setup → Permissions → Dashboard. Build produkcyjny nigdy
  nie pomija konta.
- Zła konfiguracja: jak w stagingu; build release bez poprawnej konfiguracji backendu jest odrzucany przez
  kompilator albo przy starcie i nigdy nie zachowuje się jak local-only.

### Kontrola konfiguracji przed buildem

```bash
dart run tool/check_backend_config.dart --build-mode=release --dart-define=API_BASE_URL=https://<host API>
bash tool/check_release_guard.sh            # cała macierz (sekundy): 26 kontroli, 18 musi być odrzuconych, 8 przyjętych
bash tool/check_release_guard.sh --builds   # plus trzy prawdziwe buildy release (Gradle): dwa muszą się nie skompilować, jeden musi się zbudować
```

`tool/check_backend_config.dart` stosuje dokładnie te reguły, co aplikacja przy starcie (kontrola profile lub release
bez `APP_ENV` jest kontrolą `production`; kody wyjścia: 0 poprawna, 1 błędna, 64 złe argumenty; wartości definów nigdy
nie są drukowane) i odrzuca każdy define o nazwie `dart.vm.*` (nadpisałby tryb buildu, po którym aplikacja sama się
rozpoznaje). Z `--builds` skrypt robi trzy prawdziwe, niepodpisane buildy release aplikacji na Androida
(`WATTBYTE_ALLOW_UNSIGNED_RELEASE=1`, klucz niepotrzebny): bez `API_BASE_URL` build musi się zakończyć błędem
`[WB-CONFIG-001]`, z adresem i `LOCAL_ONLY_DEV=true` błędem `[WB-CONFIG-002]`, a z poprawnym, zmyślonym adresem (arm64)
musi się zbudować, przy czym napisu paska deweloperskiego nie wolno znaleźć w `libapp.so`, a napis kontrolny binarki
release musi tam być; APK jest potem usuwany. CI uruchamia macierz i dwa testy okablowania (prawdziwe `--dart-define`
docierają do `AppConfig`) w jobie `mobile-config-guard`, trzy buildy w jobie `android`: status CONFIGURED, NOT REMOTELY
VERIFIED (`../../docs/CI.md`).

`API_BASE_URL` **nie jest sekretem** (define trafia do binarki i można go z niej odczytać), ale nie jest też
wpisany w kodzie: ustawia się go per środowisko przez `--dart-define`, `--dart-define-from-file=config/<env>.json`
(pliki `config/*.json` są ignorowane przez Git, śledzone są tylko `*.example.json`) albo, w CI, przez wejście
`api_base_url` workflow `release.yml`. `flutter test` i `flutter analyze` nie potrzebują definów (dwa testy w
`test/config/define_wiring_test.dart` pomijają się bez nich, a CI uruchamia ten plik dwa razy z prawdziwymi
definami). Build debug bez definów się kompiluje, ale uruchomiona aplikacja zatrzymuje się na ekranie błędu, więc
zielony `flutter build ... --debug` nie znaczy, że aplikacja wystartuje.

## Uruchomienie

```bash
flutter pub get
flutter gen-l10n
dart format --set-exit-if-changed lib test packages tool
flutter analyze
flutter test
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8080   # albo --dart-define=LOCAL_ONLY_DEV=true; samo `flutter run` kończy się błędem konfiguracji
```

Warianty `--dart-define` (online, local-only, staging, production): sekcja „Konfiguracja backendu” powyżej.

### Android

- `minSdk 29` (null `subscriberId` w `NetworkStatsManager` = suma wszystkich SIM).
- Uprawnienia: `PACKAGE_USAGE_STATS` (specjalne; aplikacja prowadzi do
  `Settings.ACTION_USAGE_ACCESS_SETTINGS` i rozróżnia granted / denied / unavailable),
  `POST_NOTIFICATIONS` (opcjonalne alerty). `INTERNET` (API) jest w głównym manifeście;
  build release łączy się tylko przez https (`usesCleartextTraffic="false"`), cleartext tylko w manifeście debug.
- Sesje ładowania: `ChargingWorker` – jedno zadanie WorkManager z `requiresCharging`,
  które próbkuje co 60 s przez ≤ 9 min i dokłada kolejne (łańcuch), zamiast
  niemożliwego „periodic co minutę” (minimum 15 min). System zatrzymuje je po
  odłączeniu ładowarki; `onStopped` zapisuje stan końcowy. Zużycie energii: jeden
  odczyt sticky broadcastu na minutę wyłącznie podczas ładowania.
- Widget: `WattByteWidgetProvider` + `res/layout/widget_*.xml`, dane z `home_widget`.
- Testy Kotlin (czysta logika pluginu: `DayRanges`, `BatteryValues`):
  `cd packages/wattbyte_system/android/jvm-tests && gradle test` (zwykły JVM, bez SDK).
  Uwaga: Gradle test worker nie ładuje klas ze ścieżek ze znakami spoza ASCII
  (`ClassNotFoundException`), więc przy katalogu projektu zawierającym np. „ł”
  uruchom je z kopii/ścieżki ASCII. W buildzie aplikacji ten sam problem dotyczy
  `./gradlew :wattbyte_system:testDebugUnitTest`.
- Przed publikacją podmień `signingConfig` w `android/app/build.gradle.kts` i zadeklaruj
  `PACKAGE_USAGE_STATS` w Google Play Console.

### iOS

Po otwarciu `ios/Runner.xcworkspace` w Xcode:

1. Runner → Signing & Capabilities → **App Groups** → `group.pl.wattbyte`
   (`ios/Runner/Runner.entitlements`) oraz **Background Modes**: fetch, processing (`Info.plist`).
2. File → New → Target → **Widget Extension** `WattByteWidget` (bez App Intents);
   zastąp wygenerowany plik `ios/WattByteWidget/WattByteWidget.swift`, dodaj
   `WattByteWidget.entitlements` i tę samą App Group.

Ograniczenia iOS wynikają z platformy: brak danych per aplikacja, brak liczników
mAh, brak zdarzeń ładowania w tle, liczniki `getifaddrs` są 32‑bitowe i od restartu.
UI komunikuje to wprost (notki „Szacowane”).

## Świadomie pominięte

- Miesięczny raport (JSON/CSV zawierają wszystkie dane).
- Własna ikona aplikacji i launch screen.
- 64‑bitowe liczniki iOS (`sysctl NET_RT_IFLIST2`).
- Automatyczne pobieranie taryf (prywatność).
