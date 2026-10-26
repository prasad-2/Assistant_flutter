# My Finance & Todo (offline Flutter app)

Fully offline: SQLite (sqflite) on the phone. Tabs: Home, Finance, Todo, Settings.

## Setup
1. Install Flutter (3.22+), Android SDK.
2. On Windows: double-click `setup.bat` (or run it in Command Prompt / PowerShell inside this folder).
3. `flutter run` (or `flutter build apk --release`).

### Manual steps (if setup.sh isn't usable)
- `flutter create --org com.personal --project-name my_finance_todo --platforms android .` (keep our `lib/` and `pubspec.yaml`)
- Copy `android_patch/AndroidManifest.xml` over `android/app/src/main/AndroidManifest.xml`
- Copy `android_patch/MainActivity.kt` over the generated `MainActivity.kt` (needed by local_auth)
- In `android/app/build.gradle(.kts)`: set minSdk 24, enable core library desugaring
  (`isCoreLibraryDesugaringEnabled = true` in compileOptions, and dependency
  `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")`), (`android_patch/patch_gradle.py` does this if you have Python).

## How balances work
- Amounts are stored as integer paise; shown in INR (₹1,00,000.00).
- **Own ledger** of an account = sum of its actual transactions.
- **Available** = own ledger − scheduled debits (funds block). Scheduled credits are shown in "Scheduled" but only add to available once marked actual (flip `kScheduledCreditsCountInAvailable` in `lib/db/app_database.dart` to change).
- **Actual** = own ledger + ledgers of all nested child accounts. (HDFC 1,000 → daily use 600, savings 150: HDFC actual 1,000.00, available 250.00; children actual = available.)
- Credit accounts: balance may go down to −credit limit; shown balances include the limit (available credit).
- Every add/edit/delete runs in a DB transaction and re-validates all accounts; if any actual or available balance would go negative, it is rejected ("Insufficient balance") and rolled back.
- Self transfer creates two linked entries (debit + credit); editing/deleting affects both.
- Scheduled → actual: the original scheduled date/description/value are kept and shown in the transaction details.
- Category edit/delete warns about affected transactions; a credit↔deduct change is simulated first and blocked if it would make a balance negative. Used categories can't be deleted.
- Account delete is blocked while it has child accounts or linked self-transfers.

## Security & backup
- App lock: phone biometrics/face/PIN/pattern, or an in-app password (with biometric shortcut). Required at app open, backup, restore and when changing lock settings.
- Backup saves the raw `.db` file via the system file picker; restore validates and replaces it. Lock settings/theme are not part of the backup.
- Todo reminders use exact alarms (Android may ask for the "Alarms & reminders" permission).
