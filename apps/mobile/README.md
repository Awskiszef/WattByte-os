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
widgety (`home_widget`) → `SyncQueue` (agregaty dzienne; po zalogowaniu i przy włączonej synchronizacji trafiają do `POST /api/v1/usage/sync`, zob. `docs/CLOUD_DATA.md` i `docs/SYNC_OWNERSHIP.md`) →
reguły powiadomień. Ten sam kod działa w UI (wznowienie, pull‑to‑refresh, timer
60 s) i w tle (`workmanager`).

## Konfiguracja backendu (`--dart-define`)

Każdy build WattByte potrzebuje backendu: adres API jest wkompilowany przez `--dart-define=API_BASE_URL=...`. Build bez
adresu nie jest „aplikacją lokalną”, tylko **błędną konfiguracją**; jedyny tryb bez backendu to jawny `LOCAL_ONLY_DEV=true`
i istnieje wyłącznie w buildach debug. Profile i release nie przyjmują `APP_ENV=development` ani adresu spoza publicznej
sieci (localhost, IP, nazwy jednoczłonowe, zarezerwowane domeny).

**Pełny opis (tabela definów, tryby buildu, trzy warstwy ochrony, środowiska, kontrola przed buildem) jest w jednym
miejscu: [`docs/CONFIGURATION_MOBILE.md`](../../docs/CONFIGURATION_MOBILE.md)** (po angielsku). Tu tylko polecenia na co dzień:

```bash
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8080       # symulator iOS (API z `pnpm --filter @wattbyte/api dev`)
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080        # emulator Androida → API na komputerze
flutter run --dart-define=LOCAL_ONLY_DEV=true                      # bez backendu i bez konta, tylko debug, czerwony pasek
flutter run --dart-define-from-file=config/development.json        # kopia config/development.example.json
dart run tool/check_backend_config.dart --build-mode=release --dart-define-from-file=config/production.json   # kontrola przed buildem
bash tool/check_release_guard.sh                                   # cała macierz kontroli (26 przypadków)
```

W emulatorze Androida `localhost` to sam emulator; `10.0.2.2` to alias komputera. Samo `flutter run` bez definów kończy
się ekranem „Invalid build configuration”.

## Uruchomienie

```bash
flutter pub get
flutter gen-l10n
dart format --set-exit-if-changed lib test packages tool
flutter analyze
flutter test
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8080   # albo --dart-define=LOCAL_ONLY_DEV=true; samo `flutter run` kończy się błędem konfiguracji
```

Warianty `--dart-define` (online, local-only, staging, production): [`docs/CONFIGURATION_MOBILE.md`](../../docs/CONFIGURATION_MOBILE.md).

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

Projekt zawiera już cele Runner i WattByteWidget (bundle id `pl.wattbyte.app`, widget `pl.wattbyte.app.WattByteWidget`,
App Group `group.pl.wattbyte.app`, tło: fetch + processing w `Info.plist`); skrypt `tool/ios_setup_project.rb` odtwarza
konfigurację. Wybierz zespół podpisujący w `ios/Flutter/Local.xcconfig` (kopia `Local.xcconfig.example`) albo w Xcode.
Co jest gotowe i co wymaga konta Apple: [`docs/RELEASE.md`](../../docs/RELEASE.md), sekcja iOS.

Ograniczenia iOS wynikają z platformy: brak danych per aplikacja, brak liczników mAh, brak zdarzeń ładowania w tle.
Liczniki sieciowe są 64‑bitowe (`sysctl NET_RT_IFLIST2`) i liczone od restartu urządzenia. UI komunikuje to wprost
(notki „Szacowane”).

## Świadomie pominięte

- Miesięczny raport (JSON/CSV zawierają wszystkie dane).
- Własna ikona aplikacji i launch screen.
- Automatyczne pobieranie taryf (prywatność).
