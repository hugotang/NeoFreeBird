# V6 i18N Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the remaining English placeholder values in all 15 non-English v6 localizations and prevent key, token, newline, and untranslated-value regressions.

**Architecture:** Keep English as the source-of-truth key and formatting contract. Add one PowerShell test that parses the real `.strings` files, supports per-locale runs, and allows only documented product names or native loanwords to remain byte-for-byte equal to English. Apply translations directly to the existing locale files in four independently testable batches; do not modify runtime code or build infrastructure.

**Tech Stack:** Apple `.strings` resources, PowerShell 7, Git

---

## File Map

- Create `tests/localization/Test-V6Localization.ps1`: parse all locale files and enforce key parity, non-empty values, approved English-value exceptions, ordered printf tokens, and escaped-newline counts.
- Modify the 15 `layout/Library/Application Support/BHT/BHTwitter.bundle/<locale>.lproj/Localizable.strings` files: replace the confirmed English placeholders with the exact native-language values specified below.
- Keep `layout/Library/Application Support/BHT/BHTwitter.bundle/en.lproj/Localizable.strings` unchanged as the source of truth.

### Task 1: Add The Failing Localization Contract

**Files:**
- Create: `tests/localization/Test-V6Localization.ps1`
- Read: `layout/Library/Application Support/BHT/BHTwitter.bundle/en.lproj/Localizable.strings`
- Test: `tests/localization/Test-V6Localization.ps1`

- [ ] **Step 1: Create the localization contract test**

Create `tests/localization/Test-V6Localization.ps1` with this complete content:

```powershell
param(
    [ValidateSet(
        "All", "ar", "de", "es", "fr", "hr", "id", "ja", "ko",
        "pl", "ru", "sv", "tr", "uk", "zh_CN", "zh-Hant"
    )]
    [string[]]$Locale = @("All")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$bundleRoot = Join-Path $repoRoot "layout\Library\Application Support\BHT\BHTwitter.bundle"
$supportedLocales = @(
    "ar", "de", "es", "fr", "hr", "id", "ja", "ko",
    "pl", "ru", "sv", "tr", "uk", "zh_CN", "zh-Hant"
)
$selectedLocales = if ($Locale -contains "All") {
    $supportedLocales
} else {
    @($Locale | Select-Object -Unique)
}
$failures = [System.Collections.Generic.List[string]]::new()

function Get-StringsFile {
    param([string]$Path)

    $values = @{}
    $duplicates = [System.Collections.Generic.List[string]]::new()
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ($line -match '^\s*"(?<key>(?:\\.|[^"])*)"\s*=\s*"(?<value>(?:\\.|[^"])*)"\s*;\s*$') {
            $key = $Matches.key
            if ($values.ContainsKey($key)) {
                $duplicates.Add($key)
            }
            $values[$key] = $Matches.value
        }
    }

    return [PSCustomObject]@{
        Values = $values
        Duplicates = @($duplicates)
    }
}

function Get-FormatTokens {
    param([string]$Value)

    $pattern = '(?<!%)%(?:\d+\$)?(?:@|(?:hh|h|ll|l|z|t|j)?[diuoxXfFeEgGaAcsp])'
    return @([regex]::Matches($Value, $pattern) | ForEach-Object { $_.Value })
}

function Get-EscapedNewlineCount {
    param([string]$Value)

    return [regex]::Matches($Value, '\\n').Count
}

$baseAllowedEnglishValues = @(
    "MODERN_SETTINGS_GROK_TITLE",
    "NFB_SETTINGS_TITLE"
)
$localeAllowedEnglishValues = @{
    de = @(
        "DOWNLOAD_VIDEO_NUMBER_TITLE",
        "MODERN_SETTINGS_BRANDING_TITLE",
        "MODERN_SETTINGS_DEBUG_TITLE",
        "MODERN_SETTINGS_TIMELINES_TITLE"
    )
    es = @("MODERN_SETTINGS_LAYOUT_TITLE")
    id = @("MODERN_SETTINGS_BRANDING_TITLE", "MODERN_SETTINGS_DEBUG_TITLE")
    sv = @("DOWNLOAD_VIDEO_NUMBER_TITLE")
    tr = @("DOWNLOAD_VIDEO_NUMBER_TITLE")
}

$englishPath = Join-Path $bundleRoot "en.lproj\Localizable.strings"
$englishResult = Get-StringsFile $englishPath
$english = $englishResult.Values
if ($englishResult.Duplicates.Count -gt 0) {
    $failures.Add("en contains duplicate keys: $($englishResult.Duplicates -join ', ')")
}

$actualLocales = @(
    Get-ChildItem $bundleRoot -Directory -Filter "*.lproj" |
        ForEach-Object { $_.Name -replace '\.lproj$', '' } |
        Where-Object { $_ -ne "en" } |
        Sort-Object
)
$localeSetDifference = @(Compare-Object ($supportedLocales | Sort-Object) $actualLocales)
if ($localeSetDifference.Count -gt 0) {
    $failures.Add("Locale directory set differs from the supported locale contract.")
}

foreach ($localeName in $selectedLocales) {
    $path = Join-Path $bundleRoot "$localeName.lproj\Localizable.strings"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $failures.Add("$localeName is missing Localizable.strings")
        continue
    }

    $result = Get-StringsFile $path
    $localized = $result.Values
    if ($result.Duplicates.Count -gt 0) {
        $failures.Add("$localeName contains duplicate keys: $($result.Duplicates -join ', ')")
    }

    $missingKeys = @($english.Keys | Where-Object { -not $localized.ContainsKey($_) } | Sort-Object)
    $extraKeys = @($localized.Keys | Where-Object { -not $english.ContainsKey($_) } | Sort-Object)
    if ($missingKeys.Count -gt 0) {
        $failures.Add("$localeName is missing keys: $($missingKeys -join ', ')")
    }
    if ($extraKeys.Count -gt 0) {
        $failures.Add("$localeName has extra keys: $($extraKeys -join ', ')")
    }

    $allowedEnglishValues = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($key in $baseAllowedEnglishValues) {
        [void]$allowedEnglishValues.Add($key)
    }
    if ($localeAllowedEnglishValues.ContainsKey($localeName)) {
        foreach ($key in $localeAllowedEnglishValues[$localeName]) {
            [void]$allowedEnglishValues.Add($key)
        }
    }

    foreach ($key in $english.Keys) {
        if (-not $localized.ContainsKey($key)) {
            continue
        }

        $value = $localized[$key]
        if ([string]::IsNullOrWhiteSpace($value) -or $value -ceq $key) {
            $failures.Add("$localeName has an empty or unresolved value for $key")
        }

        if ($value -ceq $english[$key] -and -not $allowedEnglishValues.Contains($key)) {
            $failures.Add("$localeName still uses English for $key")
        }

        $englishTokens = (Get-FormatTokens $english[$key]) -join "`n"
        $localizedTokens = (Get-FormatTokens $value) -join "`n"
        if ($localizedTokens -cne $englishTokens) {
            $failures.Add("$localeName changed format tokens for $key")
        }

        $englishNewlines = Get-EscapedNewlineCount $english[$key]
        $localizedNewlines = Get-EscapedNewlineCount $value
        if ($localizedNewlines -ne $englishNewlines) {
            $failures.Add("$localeName changed escaped newline count for $key")
        }
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Host "FAIL: $failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host "V6 localization contract passed: $($selectedLocales -join ', ')"
```

- [ ] **Step 2: Run the test and verify the expected red state**

Run:

```powershell
& 'tests\localization\Test-V6Localization.ps1'
```

Expected: exit code `1`, with failures such as `ar still uses English for CUSTOM_TAB_BAR_GRID_DETAIL`, `de still uses English for LEGACY_LOGIN_FAILED_TITLE`, and equivalent failures across all 15 locales. There must be no parser exception.

### Task 2: Translate Arabic, German, Spanish, And French

**Files:**
- Modify: `layout/Library/Application Support/BHT/BHTwitter.bundle/ar.lproj/Localizable.strings`
- Modify: `layout/Library/Application Support/BHT/BHTwitter.bundle/de.lproj/Localizable.strings`
- Modify: `layout/Library/Application Support/BHT/BHTwitter.bundle/es.lproj/Localizable.strings`
- Modify: `layout/Library/Application Support/BHT/BHTwitter.bundle/fr.lproj/Localizable.strings`
- Test: `tests/localization/Test-V6Localization.ps1`

- [ ] **Step 1: Apply the Arabic translations**

Replace the matching Arabic entries with these exact values:

```text
"CUSTOM_TAB_BAR_GRID_DETAIL" = "اضغط على وجهة لإضافتها أو إزالتها. اسحب الشريط أدناه لإعادة الترتيب.";
"PADLOCK_LOCKED_LABEL" = "مقفل";
"UNKNOWN_SOURCE" = "مصدر غير معروف";
"DOWNLOAD_VIDEO_NUMBER_TITLE" = "الفيديو %lu";
"UNKNOWN_ERROR" = "حدث خطأ غير معروف.";
"INSTALL_IFONT_BUTTON_TITLE" = "تطبيق iFont";
"FONT_SYSTEM_DEFAULT_SUBTITLE" = "الخط الافتراضي للنظام";
"LEGACY_LOGIN_INFO_LABEL" = "سجّل الدخول باستخدام اسم المستخدم وكلمة المرور.\n\nتسجيل الدخول عبر Google وApple غير مدعوم. إذا كان حسابك يستخدم إحداهما، فأضف كلمة مرور إليه أولًا.";
"LEGACY_LOGIN_MISSING_INPUT_TITLE" = "بيانات ناقصة";
"LEGACY_LOGIN_MISSING_INPUT_MESSAGE" = "أدخل اسم المستخدم وكلمة المرور.";
"LEGACY_LOGIN_VERIFYING_STATUS" = "جارٍ التحقق…";
"LEGACY_LOGIN_SIGNING_IN_STATUS" = "جارٍ تسجيل الدخول…";
"LEGACY_LOGIN_UNAVAILABLE_TITLE" = "غير متاح";
"LEGACY_LOGIN_CLASSES_MISSING_MESSAGE" = "فئات تسجيل الدخول غير موجودة.";
"LEGACY_LOGIN_BUILD_COMMAND_FAILED_MESSAGE" = "تعذر إنشاء الأمر.";
"LEGACY_LOGIN_CRASH_AVOIDED_TITLE" = "تم تجنب التعطل";
"LEGACY_LOGIN_UNEXPECTED_RESPONSE_TITLE" = "استجابة غير متوقعة";
"LEGACY_LOGIN_NO_TOKEN_NO_CHALLENGE_MESSAGE" = "لا يوجد رمز ولا تحدٍ.";
"LEGACY_LOGIN_CHALLENGE_MISSING_INFO_MESSAGE" = "معرّف الطلب أو عنوان URL مفقود من التحدي.";
"LEGACY_LOGIN_CHALLENGE_CLASSES_MISSING_MESSAGE" = "فئات التحدي/المضيف غير موجودة.";
"LEGACY_LOGIN_BUILD_CHALLENGE_FAILED_MESSAGE" = "تعذر إنشاء التحدي.";
"LEGACY_LOGIN_NO_TOKEN_MESSAGE" = "لم تتضمن الاستجابة رمزًا.";
"LEGACY_LOGIN_FAILED_TITLE" = "فشل تسجيل الدخول";
"LEGACY_LOGIN_NO_ACCOUNT_MESSAGE" = "لم يتم إرجاع أي حساب.";
"LEGACY_LOGIN_RATE_LIMITED_TITLE" = "يُحتمل بلوغ حد المحاولات (243)";
"LEGACY_LOGIN_RATE_LIMITED_MESSAGE" = "عدد المحاولات كبير جدًا. انتظر قليلًا أو بدّل الشبكة/VPN، ثم حاول مجددًا.\n\nالتفاصيل:\n%@";
"LEGACY_LOGIN_UNKNOWN_ERROR" = "خطأ غير معروف";
```

- [ ] **Step 2: Apply the German translations**

Replace the matching German entries with these exact values. Keep `Video %lu`, `Branding`, `Debug`, and `Timelines` unchanged because they are normal German UI loanwords covered by the test allowlist.

```text
"CUSTOM_TAB_BAR_GRID_DETAIL" = "Tippe auf ein Ziel, um es hinzuzufügen oder zu entfernen. Ziehe die Leiste unten, um die Reihenfolge zu ändern.";
"PADLOCK_LOCKED_LABEL" = "Gesperrt";
"UNKNOWN_SOURCE" = "Unbekannte Quelle";
"DOWNLOAD_VIDEO_NUMBER_TITLE" = "Video %lu";
"UNKNOWN_ERROR" = "Ein unbekannter Fehler ist aufgetreten.";
"INSTALL_IFONT_BUTTON_TITLE" = "iFont-App";
"FONT_SYSTEM_DEFAULT_SUBTITLE" = "Systemstandard";
"LEGACY_LOGIN_INFO_LABEL" = "Melde dich mit deinem Benutzernamen und Passwort an.\n\nDie Anmeldung mit Google oder Apple wird nicht unterstützt. Falls dein Konto eine dieser Methoden verwendet, füge ihm zuerst ein Passwort hinzu.";
"LEGACY_LOGIN_MISSING_INPUT_TITLE" = "Eingaben fehlen";
"LEGACY_LOGIN_MISSING_INPUT_MESSAGE" = "Gib Benutzername und Passwort ein.";
"LEGACY_LOGIN_VERIFYING_STATUS" = "Überprüfung läuft…";
"LEGACY_LOGIN_SIGNING_IN_STATUS" = "Anmeldung läuft…";
"LEGACY_LOGIN_UNAVAILABLE_TITLE" = "Nicht verfügbar";
"LEGACY_LOGIN_CLASSES_MISSING_MESSAGE" = "Anmeldeklassen fehlen.";
"LEGACY_LOGIN_BUILD_COMMAND_FAILED_MESSAGE" = "Befehl konnte nicht erstellt werden.";
"LEGACY_LOGIN_CRASH_AVOIDED_TITLE" = "Absturz verhindert";
"LEGACY_LOGIN_UNEXPECTED_RESPONSE_TITLE" = "Unerwartete Antwort";
"LEGACY_LOGIN_NO_TOKEN_NO_CHALLENGE_MESSAGE" = "Weder Token noch Challenge vorhanden.";
"LEGACY_LOGIN_CHALLENGE_MISSING_INFO_MESSAGE" = "Der Challenge fehlen die Anfrage-ID oder URL.";
"LEGACY_LOGIN_CHALLENGE_CLASSES_MISSING_MESSAGE" = "Challenge-/Host-Klassen fehlen.";
"LEGACY_LOGIN_BUILD_CHALLENGE_FAILED_MESSAGE" = "Challenge konnte nicht erstellt werden.";
"LEGACY_LOGIN_NO_TOKEN_MESSAGE" = "Die Antwort enthält kein Token.";
"LEGACY_LOGIN_FAILED_TITLE" = "Anmeldung fehlgeschlagen";
"LEGACY_LOGIN_NO_ACCOUNT_MESSAGE" = "Es wurde kein Konto zurückgegeben.";
"LEGACY_LOGIN_RATE_LIMITED_TITLE" = "Wahrscheinlich zu viele Anfragen (243)";
"LEGACY_LOGIN_RATE_LIMITED_MESSAGE" = "Zu viele Versuche. Warte etwas oder wechsle das Netzwerk/VPN und versuche es erneut.\n\nDetails:\n%@";
"LEGACY_LOGIN_UNKNOWN_ERROR" = "Unbekannter Fehler";
"THEME_SETTINGS_NAVIGATION_TITLE" = "Design";
```

- [ ] **Step 3: Apply the Spanish translations**

Replace the matching Spanish entries with these exact values. Keep the existing `General` title unchanged because it is native Spanish usage.

```text
"CUSTOM_TAB_BAR_GRID_DETAIL" = "Toca un destino para añadirlo o eliminarlo. Arrastra la barra inferior para cambiar el orden.";
"PADLOCK_LOCKED_LABEL" = "Bloqueado";
"UNKNOWN_SOURCE" = "Origen desconocido";
"DOWNLOAD_VIDEO_NUMBER_TITLE" = "Vídeo %lu";
"UNKNOWN_ERROR" = "Se produjo un error desconocido.";
"INSTALL_IFONT_BUTTON_TITLE" = "Aplicación iFont";
"FONT_SYSTEM_DEFAULT_SUBTITLE" = "Predeterminado del sistema";
"LEGACY_LOGIN_INFO_LABEL" = "Inicia sesión con tu nombre de usuario y contraseña.\n\nNo se admite el inicio de sesión con Google ni Apple. Si tu cuenta usa uno de ellos, añade primero una contraseña.";
"LEGACY_LOGIN_MISSING_INPUT_TITLE" = "Faltan datos";
"LEGACY_LOGIN_MISSING_INPUT_MESSAGE" = "Introduce el nombre de usuario y la contraseña.";
"LEGACY_LOGIN_VERIFYING_STATUS" = "Verificando…";
"LEGACY_LOGIN_SIGNING_IN_STATUS" = "Iniciando sesión…";
"LEGACY_LOGIN_UNAVAILABLE_TITLE" = "No disponible";
"LEGACY_LOGIN_CLASSES_MISSING_MESSAGE" = "Faltan las clases de inicio de sesión.";
"LEGACY_LOGIN_BUILD_COMMAND_FAILED_MESSAGE" = "No se pudo crear el comando.";
"LEGACY_LOGIN_CRASH_AVOIDED_TITLE" = "Se evitó un cierre inesperado";
"LEGACY_LOGIN_UNEXPECTED_RESPONSE_TITLE" = "Respuesta inesperada";
"LEGACY_LOGIN_NO_TOKEN_NO_CHALLENGE_MESSAGE" = "No hay token ni desafío.";
"LEGACY_LOGIN_CHALLENGE_MISSING_INFO_MESSAGE" = "Al desafío le falta el identificador de solicitud o la URL.";
"LEGACY_LOGIN_CHALLENGE_CLASSES_MISSING_MESSAGE" = "Faltan las clases de desafío o de host.";
"LEGACY_LOGIN_BUILD_CHALLENGE_FAILED_MESSAGE" = "No se pudo crear el desafío.";
"LEGACY_LOGIN_NO_TOKEN_MESSAGE" = "La respuesta no contiene ningún token.";
"LEGACY_LOGIN_FAILED_TITLE" = "Error al iniciar sesión";
"LEGACY_LOGIN_NO_ACCOUNT_MESSAGE" = "No se devolvió ninguna cuenta.";
"LEGACY_LOGIN_RATE_LIMITED_TITLE" = "Probable límite de solicitudes (243)";
"LEGACY_LOGIN_RATE_LIMITED_MESSAGE" = "Demasiados intentos. Espera un poco o cambia de red/VPN y vuelve a intentarlo.\n\nDetalles:\n%@";
"LEGACY_LOGIN_UNKNOWN_ERROR" = "Error desconocido";
"MODERN_SETTINGS_EXPERIMENTAL_TITLE" = "Laboratorio";
```

- [ ] **Step 4: Apply the French translations**

Replace the matching French entries with these exact values:

```text
"CUSTOM_TAB_BAR_GRID_DETAIL" = "Touchez une destination pour l’ajouter ou la supprimer. Faites glisser la barre ci-dessous pour modifier l’ordre.";
"PADLOCK_LOCKED_LABEL" = "Verrouillé";
"UNKNOWN_SOURCE" = "Source inconnue";
"DOWNLOAD_VIDEO_NUMBER_TITLE" = "Vidéo %lu";
"UNKNOWN_ERROR" = "Une erreur inconnue s’est produite.";
"INSTALL_IFONT_BUTTON_TITLE" = "Application iFont";
"FONT_SYSTEM_DEFAULT_SUBTITLE" = "Police système par défaut";
"LEGACY_LOGIN_INFO_LABEL" = "Connectez-vous avec votre nom d’utilisateur et votre mot de passe.\n\nLa connexion avec Google ou Apple n’est pas prise en charge. Si votre compte utilise l’un de ces services, ajoutez-lui d’abord un mot de passe.";
"LEGACY_LOGIN_MISSING_INPUT_TITLE" = "Informations manquantes";
"LEGACY_LOGIN_MISSING_INPUT_MESSAGE" = "Saisissez le nom d’utilisateur et le mot de passe.";
"LEGACY_LOGIN_VERIFYING_STATUS" = "Vérification…";
"LEGACY_LOGIN_SIGNING_IN_STATUS" = "Connexion…";
"LEGACY_LOGIN_UNAVAILABLE_TITLE" = "Indisponible";
"LEGACY_LOGIN_CLASSES_MISSING_MESSAGE" = "Les classes de connexion sont absentes.";
"LEGACY_LOGIN_BUILD_COMMAND_FAILED_MESSAGE" = "Impossible de créer la commande.";
"LEGACY_LOGIN_CRASH_AVOIDED_TITLE" = "Fermeture inattendue évitée";
"LEGACY_LOGIN_UNEXPECTED_RESPONSE_TITLE" = "Réponse inattendue";
"LEGACY_LOGIN_NO_TOKEN_NO_CHALLENGE_MESSAGE" = "Aucun jeton ni défi.";
"LEGACY_LOGIN_CHALLENGE_MISSING_INFO_MESSAGE" = "L’identifiant de requête ou l’URL du défi est absent.";
"LEGACY_LOGIN_CHALLENGE_CLASSES_MISSING_MESSAGE" = "Les classes du défi ou de l’hôte sont absentes.";
"LEGACY_LOGIN_BUILD_CHALLENGE_FAILED_MESSAGE" = "Impossible de créer le défi.";
"LEGACY_LOGIN_NO_TOKEN_MESSAGE" = "La réponse ne contient aucun jeton.";
"LEGACY_LOGIN_FAILED_TITLE" = "Échec de la connexion";
"LEGACY_LOGIN_NO_ACCOUNT_MESSAGE" = "Aucun compte n’a été renvoyé.";
"LEGACY_LOGIN_RATE_LIMITED_TITLE" = "Limite de requêtes probablement atteinte (243)";
"LEGACY_LOGIN_RATE_LIMITED_MESSAGE" = "Trop de tentatives. Patientez un moment ou changez de réseau/VPN, puis réessayez.\n\nDétails :\n%@";
"LEGACY_LOGIN_UNKNOWN_ERROR" = "Erreur inconnue";
```

- [ ] **Step 5: Verify this locale batch turns green**

Run:

```powershell
& 'tests\localization\Test-V6Localization.ps1' -Locale ar,de,es,fr
```

Expected: exit code `0` and `V6 localization contract passed: ar, de, es, fr`.

- [ ] **Step 6: Check and commit the first batch**

Run:

```powershell
git diff --check
git add -- tests/localization/Test-V6Localization.ps1 "layout/Library/Application Support/BHT/BHTwitter.bundle/ar.lproj/Localizable.strings" "layout/Library/Application Support/BHT/BHTwitter.bundle/de.lproj/Localizable.strings" "layout/Library/Application Support/BHT/BHTwitter.bundle/es.lproj/Localizable.strings" "layout/Library/Application Support/BHT/BHTwitter.bundle/fr.lproj/Localizable.strings"
git commit -m "Add initial v6 localization coverage"
```

Expected: `git diff --check` exits `0`, then one commit containing the test and the four locale files.

### Task 3: Translate Croatian, Indonesian, Swedish, And Turkish

**Files:**
- Modify: `layout/Library/Application Support/BHT/BHTwitter.bundle/hr.lproj/Localizable.strings`
- Modify: `layout/Library/Application Support/BHT/BHTwitter.bundle/id.lproj/Localizable.strings`
- Modify: `layout/Library/Application Support/BHT/BHTwitter.bundle/sv.lproj/Localizable.strings`
- Modify: `layout/Library/Application Support/BHT/BHTwitter.bundle/tr.lproj/Localizable.strings`
- Test: `tests/localization/Test-V6Localization.ps1`

- [ ] **Step 1: Apply the Croatian translations**

Replace the matching Croatian entries with these exact values:

```text
"CUSTOM_TAB_BAR_GRID_DETAIL" = "Dodirni odredište da ga dodaš ili ukloniš. Povuci traku ispod za promjenu redoslijeda.";
"PADLOCK_LOCKED_LABEL" = "Zaključano";
"UNKNOWN_SOURCE" = "Nepoznat izvor";
"DOWNLOAD_VIDEO_NUMBER_TITLE" = "Videozapis %lu";
"UNKNOWN_ERROR" = "Došlo je do nepoznate pogreške.";
"INSTALL_IFONT_BUTTON_TITLE" = "Aplikacija iFont";
"FONT_SYSTEM_DEFAULT_SUBTITLE" = "Zadana postavka sustava";
"LEGACY_LOGIN_INFO_LABEL" = "Prijavi se korisničkim imenom i lozinkom.\n\nPrijava putem Googlea i Applea nije podržana. Ako tvoj račun koristi jednu od tih usluga, prvo mu dodaj lozinku.";
"LEGACY_LOGIN_MISSING_INPUT_TITLE" = "Nedostaju podaci";
"LEGACY_LOGIN_MISSING_INPUT_MESSAGE" = "Unesi korisničko ime i lozinku.";
"LEGACY_LOGIN_VERIFYING_STATUS" = "Provjera…";
"LEGACY_LOGIN_SIGNING_IN_STATUS" = "Prijava…";
"LEGACY_LOGIN_UNAVAILABLE_TITLE" = "Nije dostupno";
"LEGACY_LOGIN_CLASSES_MISSING_MESSAGE" = "Nedostaju klase za prijavu.";
"LEGACY_LOGIN_BUILD_COMMAND_FAILED_MESSAGE" = "Nije moguće izraditi naredbu.";
"LEGACY_LOGIN_CRASH_AVOIDED_TITLE" = "Rušenje je spriječeno";
"LEGACY_LOGIN_UNEXPECTED_RESPONSE_TITLE" = "Neočekivan odgovor";
"LEGACY_LOGIN_NO_TOKEN_NO_CHALLENGE_MESSAGE" = "Nema tokena ni izazova.";
"LEGACY_LOGIN_CHALLENGE_MISSING_INFO_MESSAGE" = "Izazovu nedostaje ID zahtjeva ili URL.";
"LEGACY_LOGIN_CHALLENGE_CLASSES_MISSING_MESSAGE" = "Nedostaju klase izazova/hosta.";
"LEGACY_LOGIN_BUILD_CHALLENGE_FAILED_MESSAGE" = "Nije moguće izraditi izazov.";
"LEGACY_LOGIN_NO_TOKEN_MESSAGE" = "Odgovor ne sadrži token.";
"LEGACY_LOGIN_FAILED_TITLE" = "Prijava nije uspjela";
"LEGACY_LOGIN_NO_ACCOUNT_MESSAGE" = "Nije vraćen nijedan račun.";
"LEGACY_LOGIN_RATE_LIMITED_TITLE" = "Vjerojatno ograničenje zahtjeva (243)";
"LEGACY_LOGIN_RATE_LIMITED_MESSAGE" = "Previše pokušaja. Pričekaj malo ili promijeni mrežu/VPN pa pokušaj ponovno.\n\nPojedinosti:\n%@";
"LEGACY_LOGIN_UNKNOWN_ERROR" = "Nepoznata pogreška";
```

- [ ] **Step 2: Apply the Indonesian translations**

Replace the matching Indonesian entries with these exact values. Keep `Branding` and `Debug` unchanged as established Indonesian technical loanwords covered by the test allowlist.

```text
"CUSTOM_TAB_BAR_GRID_DETAIL" = "Ketuk tujuan untuk menambahkan atau menghapusnya. Seret bilah di bawah untuk mengubah urutan.";
"PADLOCK_LOCKED_LABEL" = "Terkunci";
"UNKNOWN_SOURCE" = "Sumber tidak diketahui";
"DOWNLOAD_VIDEO_NUMBER_TITLE" = "Video ke-%lu";
"UNKNOWN_ERROR" = "Terjadi kesalahan yang tidak diketahui.";
"INSTALL_IFONT_BUTTON_TITLE" = "Aplikasi iFont";
"FONT_SYSTEM_DEFAULT_SUBTITLE" = "Bawaan Sistem";
"LEGACY_LOGIN_INFO_LABEL" = "Masuk dengan nama pengguna dan kata sandi.\n\nLogin dengan Google dan Apple tidak didukung. Jika akun Anda menggunakan salah satunya, tambahkan kata sandi terlebih dahulu.";
"LEGACY_LOGIN_MISSING_INPUT_TITLE" = "Data belum lengkap";
"LEGACY_LOGIN_MISSING_INPUT_MESSAGE" = "Masukkan nama pengguna dan kata sandi.";
"LEGACY_LOGIN_VERIFYING_STATUS" = "Memverifikasi…";
"LEGACY_LOGIN_SIGNING_IN_STATUS" = "Sedang masuk…";
"LEGACY_LOGIN_UNAVAILABLE_TITLE" = "Tidak tersedia";
"LEGACY_LOGIN_CLASSES_MISSING_MESSAGE" = "Kelas login tidak ditemukan.";
"LEGACY_LOGIN_BUILD_COMMAND_FAILED_MESSAGE" = "Tidak dapat membuat perintah.";
"LEGACY_LOGIN_CRASH_AVOIDED_TITLE" = "Crash berhasil dicegah";
"LEGACY_LOGIN_UNEXPECTED_RESPONSE_TITLE" = "Respons tidak terduga";
"LEGACY_LOGIN_NO_TOKEN_NO_CHALLENGE_MESSAGE" = "Tidak ada token maupun tantangan.";
"LEGACY_LOGIN_CHALLENGE_MISSING_INFO_MESSAGE" = "ID permintaan atau URL pada tantangan tidak ditemukan.";
"LEGACY_LOGIN_CHALLENGE_CLASSES_MISSING_MESSAGE" = "Kelas tantangan/host tidak ditemukan.";
"LEGACY_LOGIN_BUILD_CHALLENGE_FAILED_MESSAGE" = "Tidak dapat membuat tantangan.";
"LEGACY_LOGIN_NO_TOKEN_MESSAGE" = "Respons tidak berisi token.";
"LEGACY_LOGIN_FAILED_TITLE" = "Login gagal";
"LEGACY_LOGIN_NO_ACCOUNT_MESSAGE" = "Tidak ada akun yang dikembalikan.";
"LEGACY_LOGIN_RATE_LIMITED_TITLE" = "Kemungkinan terkena batas permintaan (243)";
"LEGACY_LOGIN_RATE_LIMITED_MESSAGE" = "Terlalu banyak percobaan. Tunggu sebentar atau ganti jaringan/VPN, lalu coba lagi.\n\nDetail:\n%@";
"LEGACY_LOGIN_UNKNOWN_ERROR" = "Kesalahan tidak diketahui";
```

- [ ] **Step 3: Apply the Swedish translations**

Replace the matching Swedish entries with these exact values. Keep `Video %lu` unchanged because it is natural Swedish usage covered by the test allowlist.

```text
"CUSTOM_TAB_BAR_GRID_DETAIL" = "Tryck på en destination för att lägga till eller ta bort den. Dra fältet nedan för att ändra ordningen.";
"PADLOCK_LOCKED_LABEL" = "Låst";
"UNKNOWN_SOURCE" = "Okänd källa";
"DOWNLOAD_VIDEO_NUMBER_TITLE" = "Video %lu";
"UNKNOWN_ERROR" = "Ett okänt fel inträffade.";
"INSTALL_IFONT_BUTTON_TITLE" = "iFont-appen";
"FONT_SYSTEM_DEFAULT_SUBTITLE" = "Systemets standard";
"LEGACY_LOGIN_INFO_LABEL" = "Logga in med ditt användarnamn och lösenord.\n\nInloggning med Google och Apple stöds inte. Om ditt konto använder någon av dem måste du först lägga till ett lösenord.";
"LEGACY_LOGIN_MISSING_INPUT_TITLE" = "Uppgifter saknas";
"LEGACY_LOGIN_MISSING_INPUT_MESSAGE" = "Ange användarnamn och lösenord.";
"LEGACY_LOGIN_VERIFYING_STATUS" = "Verifierar…";
"LEGACY_LOGIN_SIGNING_IN_STATUS" = "Loggar in…";
"LEGACY_LOGIN_UNAVAILABLE_TITLE" = "Inte tillgängligt";
"LEGACY_LOGIN_CLASSES_MISSING_MESSAGE" = "Inloggningsklasser saknas.";
"LEGACY_LOGIN_BUILD_COMMAND_FAILED_MESSAGE" = "Det gick inte att skapa kommandot.";
"LEGACY_LOGIN_CRASH_AVOIDED_TITLE" = "Krasch förhindrad";
"LEGACY_LOGIN_UNEXPECTED_RESPONSE_TITLE" = "Oväntat svar";
"LEGACY_LOGIN_NO_TOKEN_NO_CHALLENGE_MESSAGE" = "Varken token eller utmaning finns.";
"LEGACY_LOGIN_CHALLENGE_MISSING_INFO_MESSAGE" = "Utmaningen saknar begärande-ID eller URL.";
"LEGACY_LOGIN_CHALLENGE_CLASSES_MISSING_MESSAGE" = "Klasser för utmaning eller värd saknas.";
"LEGACY_LOGIN_BUILD_CHALLENGE_FAILED_MESSAGE" = "Det gick inte att skapa utmaningen.";
"LEGACY_LOGIN_NO_TOKEN_MESSAGE" = "Svaret innehåller ingen token.";
"LEGACY_LOGIN_FAILED_TITLE" = "Inloggningen misslyckades";
"LEGACY_LOGIN_NO_ACCOUNT_MESSAGE" = "Inget konto returnerades.";
"LEGACY_LOGIN_RATE_LIMITED_TITLE" = "Troligen nådd anropsgräns (243)";
"LEGACY_LOGIN_RATE_LIMITED_MESSAGE" = "För många försök. Vänta en stund eller byt nätverk/VPN och försök igen.\n\nDetaljer:\n%@";
"LEGACY_LOGIN_UNKNOWN_ERROR" = "Okänt fel";
```

- [ ] **Step 4: Apply the Turkish translations**

Replace the matching Turkish entries with these exact values. Keep `Video %lu` unchanged because it is natural Turkish usage covered by the test allowlist.

```text
"CUSTOM_TAB_BAR_GRID_DETAIL" = "Eklemek veya kaldırmak için bir hedefe dokunun. Sıralamayı değiştirmek için aşağıdaki çubuğu sürükleyin.";
"PADLOCK_LOCKED_LABEL" = "Kilitli";
"UNKNOWN_SOURCE" = "Bilinmeyen kaynak";
"DOWNLOAD_VIDEO_NUMBER_TITLE" = "Video %lu";
"UNKNOWN_ERROR" = "Bilinmeyen bir hata oluştu.";
"INSTALL_IFONT_BUTTON_TITLE" = "iFont uygulaması";
"FONT_SYSTEM_DEFAULT_SUBTITLE" = "Sistem Varsayılanı";
"LEGACY_LOGIN_INFO_LABEL" = "Kullanıcı adınız ve şifrenizle giriş yapın.\n\nGoogle ve Apple ile giriş desteklenmez. Hesabınız bunlardan birini kullanıyorsa önce hesabınıza bir şifre ekleyin.";
"LEGACY_LOGIN_MISSING_INPUT_TITLE" = "Eksik bilgi";
"LEGACY_LOGIN_MISSING_INPUT_MESSAGE" = "Kullanıcı adı ve şifre girin.";
"LEGACY_LOGIN_VERIFYING_STATUS" = "Doğrulanıyor…";
"LEGACY_LOGIN_SIGNING_IN_STATUS" = "Giriş yapılıyor…";
"LEGACY_LOGIN_UNAVAILABLE_TITLE" = "Kullanılamıyor";
"LEGACY_LOGIN_CLASSES_MISSING_MESSAGE" = "Giriş sınıfları eksik.";
"LEGACY_LOGIN_BUILD_COMMAND_FAILED_MESSAGE" = "Komut oluşturulamadı.";
"LEGACY_LOGIN_CRASH_AVOIDED_TITLE" = "Çökme önlendi";
"LEGACY_LOGIN_UNEXPECTED_RESPONSE_TITLE" = "Beklenmeyen yanıt";
"LEGACY_LOGIN_NO_TOKEN_NO_CHALLENGE_MESSAGE" = "Token veya doğrulama isteği yok.";
"LEGACY_LOGIN_CHALLENGE_MISSING_INFO_MESSAGE" = "Doğrulama isteğinde istek kimliği veya URL eksik.";
"LEGACY_LOGIN_CHALLENGE_CLASSES_MISSING_MESSAGE" = "Doğrulama/ana makine sınıfları eksik.";
"LEGACY_LOGIN_BUILD_CHALLENGE_FAILED_MESSAGE" = "Doğrulama isteği oluşturulamadı.";
"LEGACY_LOGIN_NO_TOKEN_MESSAGE" = "Yanıtta token yok.";
"LEGACY_LOGIN_FAILED_TITLE" = "Giriş başarısız";
"LEGACY_LOGIN_NO_ACCOUNT_MESSAGE" = "Herhangi bir hesap döndürülmedi.";
"LEGACY_LOGIN_RATE_LIMITED_TITLE" = "Muhtemel istek sınırı (243)";
"LEGACY_LOGIN_RATE_LIMITED_MESSAGE" = "Çok fazla deneme yapıldı. Bir süre bekleyin veya ağ/VPN değiştirip tekrar deneyin.\n\nAyrıntılar:\n%@";
"LEGACY_LOGIN_UNKNOWN_ERROR" = "Bilinmeyen hata";
```

- [ ] **Step 5: Verify this locale batch turns green**

Run:

```powershell
& 'tests\localization\Test-V6Localization.ps1' -Locale hr,id,sv,tr
```

Expected: exit code `0` and `V6 localization contract passed: hr, id, sv, tr`.

- [ ] **Step 6: Check and commit the second batch**

Run:

```powershell
git diff --check
git add -- "layout/Library/Application Support/BHT/BHTwitter.bundle/hr.lproj/Localizable.strings" "layout/Library/Application Support/BHT/BHTwitter.bundle/id.lproj/Localizable.strings" "layout/Library/Application Support/BHT/BHTwitter.bundle/sv.lproj/Localizable.strings" "layout/Library/Application Support/BHT/BHTwitter.bundle/tr.lproj/Localizable.strings"
git commit -m "Translate v6 Croatian Indonesian Swedish and Turkish"
```

Expected: `git diff --check` exits `0`, then one commit containing only these four locale files.

### Task 4: Translate Polish, Russian, And Ukrainian

**Files:**
- Modify: `layout/Library/Application Support/BHT/BHTwitter.bundle/pl.lproj/Localizable.strings`
- Modify: `layout/Library/Application Support/BHT/BHTwitter.bundle/ru.lproj/Localizable.strings`
- Modify: `layout/Library/Application Support/BHT/BHTwitter.bundle/uk.lproj/Localizable.strings`
- Test: `tests/localization/Test-V6Localization.ps1`

- [ ] **Step 1: Apply the Polish translations**

Replace the matching Polish entries with these exact values:

```text
"CUSTOM_TAB_BAR_GRID_DETAIL" = "Stuknij miejsce docelowe, aby je dodać lub usunąć. Przeciągnij pasek poniżej, aby zmienić kolejność.";
"PADLOCK_LOCKED_LABEL" = "Zablokowane";
"UNKNOWN_SOURCE" = "Nieznane źródło";
"DOWNLOAD_VIDEO_NUMBER_TITLE" = "Film %lu";
"UNKNOWN_ERROR" = "Wystąpił nieznany błąd.";
"INSTALL_IFONT_BUTTON_TITLE" = "Aplikacja iFont";
"FONT_SYSTEM_DEFAULT_SUBTITLE" = "Domyślne systemowe";
"LEGACY_LOGIN_INFO_LABEL" = "Zaloguj się przy użyciu nazwy użytkownika i hasła.\n\nLogowanie przez Google i Apple nie jest obsługiwane. Jeśli Twoje konto używa jednej z tych metod, najpierw dodaj do niego hasło.";
"LEGACY_LOGIN_MISSING_INPUT_TITLE" = "Brakujące dane";
"LEGACY_LOGIN_MISSING_INPUT_MESSAGE" = "Wprowadź nazwę użytkownika i hasło.";
"LEGACY_LOGIN_VERIFYING_STATUS" = "Weryfikowanie…";
"LEGACY_LOGIN_SIGNING_IN_STATUS" = "Logowanie…";
"LEGACY_LOGIN_UNAVAILABLE_TITLE" = "Niedostępne";
"LEGACY_LOGIN_CLASSES_MISSING_MESSAGE" = "Brakuje klas logowania.";
"LEGACY_LOGIN_BUILD_COMMAND_FAILED_MESSAGE" = "Nie udało się utworzyć polecenia.";
"LEGACY_LOGIN_CRASH_AVOIDED_TITLE" = "Zapobiegnięto awarii";
"LEGACY_LOGIN_UNEXPECTED_RESPONSE_TITLE" = "Nieoczekiwana odpowiedź";
"LEGACY_LOGIN_NO_TOKEN_NO_CHALLENGE_MESSAGE" = "Brak tokenu i wyzwania.";
"LEGACY_LOGIN_CHALLENGE_MISSING_INFO_MESSAGE" = "W wyzwaniu brakuje identyfikatora żądania lub adresu URL.";
"LEGACY_LOGIN_CHALLENGE_CLASSES_MISSING_MESSAGE" = "Brakuje klas wyzwania lub hosta.";
"LEGACY_LOGIN_BUILD_CHALLENGE_FAILED_MESSAGE" = "Nie udało się utworzyć wyzwania.";
"LEGACY_LOGIN_NO_TOKEN_MESSAGE" = "Odpowiedź nie zawiera tokenu.";
"LEGACY_LOGIN_FAILED_TITLE" = "Logowanie nie powiodło się";
"LEGACY_LOGIN_NO_ACCOUNT_MESSAGE" = "Nie zwrócono żadnego konta.";
"LEGACY_LOGIN_RATE_LIMITED_TITLE" = "Prawdopodobny limit żądań (243)";
"LEGACY_LOGIN_RATE_LIMITED_MESSAGE" = "Zbyt wiele prób. Poczekaj chwilę lub zmień sieć/VPN, a następnie spróbuj ponownie.\n\nSzczegóły:\n%@";
"LEGACY_LOGIN_UNKNOWN_ERROR" = "Nieznany błąd";
"MODERN_SETTINGS_BRANDING_TITLE" = "Marka";
```

- [ ] **Step 2: Apply the Russian translations**

Replace the matching Russian entries with these exact values:

```text
"CUSTOM_TAB_BAR_GRID_DETAIL" = "Нажмите пункт, чтобы добавить или удалить его. Перетащите панель ниже, чтобы изменить порядок.";
"PADLOCK_LOCKED_LABEL" = "Заблокировано";
"UNKNOWN_SOURCE" = "Неизвестный источник";
"DOWNLOAD_VIDEO_NUMBER_TITLE" = "Видео %lu";
"UNKNOWN_ERROR" = "Произошла неизвестная ошибка.";
"INSTALL_IFONT_BUTTON_TITLE" = "Приложение iFont";
"FONT_SYSTEM_DEFAULT_SUBTITLE" = "Системный шрифт";
"LEGACY_LOGIN_INFO_LABEL" = "Войдите с помощью имени пользователя и пароля.\n\nВход через Google и Apple не поддерживается. Если ваша учётная запись использует один из этих способов, сначала добавьте к ней пароль.";
"LEGACY_LOGIN_MISSING_INPUT_TITLE" = "Не все поля заполнены";
"LEGACY_LOGIN_MISSING_INPUT_MESSAGE" = "Введите имя пользователя и пароль.";
"LEGACY_LOGIN_VERIFYING_STATUS" = "Проверка…";
"LEGACY_LOGIN_SIGNING_IN_STATUS" = "Выполняется вход…";
"LEGACY_LOGIN_UNAVAILABLE_TITLE" = "Недоступно";
"LEGACY_LOGIN_CLASSES_MISSING_MESSAGE" = "Отсутствуют классы входа.";
"LEGACY_LOGIN_BUILD_COMMAND_FAILED_MESSAGE" = "Не удалось создать команду.";
"LEGACY_LOGIN_CRASH_AVOIDED_TITLE" = "Сбой предотвращён";
"LEGACY_LOGIN_UNEXPECTED_RESPONSE_TITLE" = "Неожиданный ответ";
"LEGACY_LOGIN_NO_TOKEN_NO_CHALLENGE_MESSAGE" = "Нет ни токена, ни проверки.";
"LEGACY_LOGIN_CHALLENGE_MISSING_INFO_MESSAGE" = "В проверке отсутствует ID запроса или URL.";
"LEGACY_LOGIN_CHALLENGE_CLASSES_MISSING_MESSAGE" = "Отсутствуют классы проверки или хоста.";
"LEGACY_LOGIN_BUILD_CHALLENGE_FAILED_MESSAGE" = "Не удалось создать запрос проверки.";
"LEGACY_LOGIN_NO_TOKEN_MESSAGE" = "В ответе нет токена.";
"LEGACY_LOGIN_FAILED_TITLE" = "Не удалось войти";
"LEGACY_LOGIN_NO_ACCOUNT_MESSAGE" = "Учётная запись не была возвращена.";
"LEGACY_LOGIN_RATE_LIMITED_TITLE" = "Вероятно, достигнут лимит запросов (243)";
"LEGACY_LOGIN_RATE_LIMITED_MESSAGE" = "Слишком много попыток. Подождите или смените сеть/VPN, затем повторите попытку.\n\nПодробности:\n%@";
"LEGACY_LOGIN_UNKNOWN_ERROR" = "Неизвестная ошибка";
```

- [ ] **Step 3: Apply the Ukrainian translations**

Replace the matching Ukrainian entries with these exact values:

```text
"CUSTOM_TAB_BAR_GRID_DETAIL" = "Торкніться пункту, щоб додати або видалити його. Перетягніть панель нижче, щоб змінити порядок.";
"PADLOCK_LOCKED_LABEL" = "Заблоковано";
"UNKNOWN_SOURCE" = "Невідоме джерело";
"DOWNLOAD_VIDEO_NUMBER_TITLE" = "Відео %lu";
"UNKNOWN_ERROR" = "Сталася невідома помилка.";
"INSTALL_IFONT_BUTTON_TITLE" = "Застосунок iFont";
"FONT_SYSTEM_DEFAULT_SUBTITLE" = "Системний шрифт";
"LEGACY_LOGIN_INFO_LABEL" = "Увійдіть за допомогою імені користувача та пароля.\n\nВхід через Google і Apple не підтримується. Якщо ваш обліковий запис використовує один із цих способів, спочатку додайте до нього пароль.";
"LEGACY_LOGIN_MISSING_INPUT_TITLE" = "Не всі дані введено";
"LEGACY_LOGIN_MISSING_INPUT_MESSAGE" = "Введіть ім’я користувача та пароль.";
"LEGACY_LOGIN_VERIFYING_STATUS" = "Перевірка…";
"LEGACY_LOGIN_SIGNING_IN_STATUS" = "Вхід…";
"LEGACY_LOGIN_UNAVAILABLE_TITLE" = "Недоступно";
"LEGACY_LOGIN_CLASSES_MISSING_MESSAGE" = "Відсутні класи входу.";
"LEGACY_LOGIN_BUILD_COMMAND_FAILED_MESSAGE" = "Не вдалося створити команду.";
"LEGACY_LOGIN_CRASH_AVOIDED_TITLE" = "Збій попереджено";
"LEGACY_LOGIN_UNEXPECTED_RESPONSE_TITLE" = "Неочікувана відповідь";
"LEGACY_LOGIN_NO_TOKEN_NO_CHALLENGE_MESSAGE" = "Немає ні токена, ні перевірки.";
"LEGACY_LOGIN_CHALLENGE_MISSING_INFO_MESSAGE" = "У перевірці відсутній ідентифікатор запиту або URL.";
"LEGACY_LOGIN_CHALLENGE_CLASSES_MISSING_MESSAGE" = "Відсутні класи перевірки або хоста.";
"LEGACY_LOGIN_BUILD_CHALLENGE_FAILED_MESSAGE" = "Не вдалося створити перевірку.";
"LEGACY_LOGIN_NO_TOKEN_MESSAGE" = "У відповіді немає токена.";
"LEGACY_LOGIN_FAILED_TITLE" = "Не вдалося ввійти";
"LEGACY_LOGIN_NO_ACCOUNT_MESSAGE" = "Обліковий запис не повернуто.";
"LEGACY_LOGIN_RATE_LIMITED_TITLE" = "Імовірно досягнуто ліміту запитів (243)";
"LEGACY_LOGIN_RATE_LIMITED_MESSAGE" = "Забагато спроб. Зачекайте або змініть мережу/VPN, а потім повторіть спробу.\n\nДокладніше:\n%@";
"LEGACY_LOGIN_UNKNOWN_ERROR" = "Невідома помилка";
"MODERN_SETTINGS_EXPERIMENTAL_TITLE" = "Лабораторія";
```

- [ ] **Step 4: Verify this locale batch turns green**

Run:

```powershell
& 'tests\localization\Test-V6Localization.ps1' -Locale pl,ru,uk
```

Expected: exit code `0` and `V6 localization contract passed: pl, ru, uk`.

- [ ] **Step 5: Check and commit the Slavic batch**

Run:

```powershell
git diff --check
git add -- "layout/Library/Application Support/BHT/BHTwitter.bundle/pl.lproj/Localizable.strings" "layout/Library/Application Support/BHT/BHTwitter.bundle/ru.lproj/Localizable.strings" "layout/Library/Application Support/BHT/BHTwitter.bundle/uk.lproj/Localizable.strings"
git commit -m "Translate v6 Polish Russian and Ukrainian"
```

Expected: `git diff --check` exits `0`, then one commit containing only these three locale files.

### Task 5: Translate Japanese, Korean, Simplified Chinese, And Traditional Chinese

**Files:**
- Modify: `layout/Library/Application Support/BHT/BHTwitter.bundle/ja.lproj/Localizable.strings`
- Modify: `layout/Library/Application Support/BHT/BHTwitter.bundle/ko.lproj/Localizable.strings`
- Modify: `layout/Library/Application Support/BHT/BHTwitter.bundle/zh_CN.lproj/Localizable.strings`
- Modify: `layout/Library/Application Support/BHT/BHTwitter.bundle/zh-Hant.lproj/Localizable.strings`
- Test: `tests/localization/Test-V6Localization.ps1`

- [ ] **Step 1: Apply the Japanese translations**

Replace the matching Japanese entries with these exact values:

```text
"CUSTOM_TAB_BAR_GRID_DETAIL" = "項目をタップして追加または削除します。下のバーをドラッグして並べ替えます。";
"PADLOCK_LOCKED_LABEL" = "ロック中";
"UNKNOWN_SOURCE" = "不明なソース";
"DOWNLOAD_VIDEO_NUMBER_TITLE" = "動画%lu";
"UNKNOWN_ERROR" = "不明なエラーが発生しました。";
"INSTALL_IFONT_BUTTON_TITLE" = "iFontアプリ";
"FONT_SYSTEM_DEFAULT_SUBTITLE" = "システムデフォルト";
"LEGACY_LOGIN_INFO_LABEL" = "ユーザー名とパスワードでログインしてください。\n\nGoogleおよびAppleでのログインには対応していません。これらの方法を使用しているアカウントでは、先にパスワードを追加してください。";
"LEGACY_LOGIN_MISSING_INPUT_TITLE" = "入力が不足しています";
"LEGACY_LOGIN_MISSING_INPUT_MESSAGE" = "ユーザー名とパスワードを入力してください。";
"LEGACY_LOGIN_VERIFYING_STATUS" = "確認中…";
"LEGACY_LOGIN_SIGNING_IN_STATUS" = "ログイン中…";
"LEGACY_LOGIN_UNAVAILABLE_TITLE" = "利用できません";
"LEGACY_LOGIN_CLASSES_MISSING_MESSAGE" = "ログインクラスが見つかりません。";
"LEGACY_LOGIN_BUILD_COMMAND_FAILED_MESSAGE" = "コマンドを作成できませんでした。";
"LEGACY_LOGIN_CRASH_AVOIDED_TITLE" = "クラッシュを回避しました";
"LEGACY_LOGIN_UNEXPECTED_RESPONSE_TITLE" = "予期しないレスポンス";
"LEGACY_LOGIN_NO_TOKEN_NO_CHALLENGE_MESSAGE" = "トークンもチャレンジもありません。";
"LEGACY_LOGIN_CHALLENGE_MISSING_INFO_MESSAGE" = "チャレンジにリクエストIDまたはURLがありません。";
"LEGACY_LOGIN_CHALLENGE_CLASSES_MISSING_MESSAGE" = "チャレンジまたはホストのクラスが見つかりません。";
"LEGACY_LOGIN_BUILD_CHALLENGE_FAILED_MESSAGE" = "チャレンジを作成できませんでした。";
"LEGACY_LOGIN_NO_TOKEN_MESSAGE" = "レスポンスにトークンがありません。";
"LEGACY_LOGIN_FAILED_TITLE" = "ログインに失敗しました";
"LEGACY_LOGIN_NO_ACCOUNT_MESSAGE" = "アカウントが返されませんでした。";
"LEGACY_LOGIN_RATE_LIMITED_TITLE" = "レート制限の可能性があります（243）";
"LEGACY_LOGIN_RATE_LIMITED_MESSAGE" = "試行回数が多すぎます。しばらく待つか、ネットワーク/VPNを切り替えてから再試行してください。\n\n詳細：\n%@";
"LEGACY_LOGIN_UNKNOWN_ERROR" = "不明なエラー";
"COOL_KIDS_SECTION_HEADER_TITLE" = "クールな仲間たち";
```

- [ ] **Step 2: Apply the Korean translations**

Replace the matching Korean entries with these exact values:

```text
"CUSTOM_TAB_BAR_GRID_DETAIL" = "항목을 탭하여 추가하거나 제거하세요. 아래 막대를 드래그하여 순서를 변경하세요.";
"PADLOCK_LOCKED_LABEL" = "잠김";
"UNKNOWN_SOURCE" = "알 수 없는 소스";
"DOWNLOAD_VIDEO_NUMBER_TITLE" = "동영상 %lu";
"UNKNOWN_ERROR" = "알 수 없는 오류가 발생했습니다.";
"INSTALL_IFONT_BUTTON_TITLE" = "iFont 앱";
"FONT_SYSTEM_DEFAULT_SUBTITLE" = "시스템 기본값";
"LEGACY_LOGIN_INFO_LABEL" = "사용자 이름과 비밀번호로 로그인하세요.\n\nGoogle 및 Apple 로그인은 지원되지 않습니다. 해당 방식으로 만든 계정은 먼저 비밀번호를 추가하세요.";
"LEGACY_LOGIN_MISSING_INPUT_TITLE" = "입력 누락";
"LEGACY_LOGIN_MISSING_INPUT_MESSAGE" = "사용자 이름과 비밀번호를 입력하세요.";
"LEGACY_LOGIN_VERIFYING_STATUS" = "확인 중…";
"LEGACY_LOGIN_SIGNING_IN_STATUS" = "로그인 중…";
"LEGACY_LOGIN_UNAVAILABLE_TITLE" = "사용할 수 없음";
"LEGACY_LOGIN_CLASSES_MISSING_MESSAGE" = "로그인 클래스가 없습니다.";
"LEGACY_LOGIN_BUILD_COMMAND_FAILED_MESSAGE" = "명령을 생성할 수 없습니다.";
"LEGACY_LOGIN_CRASH_AVOIDED_TITLE" = "충돌 방지됨";
"LEGACY_LOGIN_UNEXPECTED_RESPONSE_TITLE" = "예기치 않은 응답";
"LEGACY_LOGIN_NO_TOKEN_NO_CHALLENGE_MESSAGE" = "토큰과 챌린지가 없습니다.";
"LEGACY_LOGIN_CHALLENGE_MISSING_INFO_MESSAGE" = "챌린지에 요청 ID 또는 URL이 없습니다.";
"LEGACY_LOGIN_CHALLENGE_CLASSES_MISSING_MESSAGE" = "챌린지/호스트 클래스가 없습니다.";
"LEGACY_LOGIN_BUILD_CHALLENGE_FAILED_MESSAGE" = "챌린지를 생성할 수 없습니다.";
"LEGACY_LOGIN_NO_TOKEN_MESSAGE" = "응답에 토큰이 없습니다.";
"LEGACY_LOGIN_FAILED_TITLE" = "로그인 실패";
"LEGACY_LOGIN_NO_ACCOUNT_MESSAGE" = "반환된 계정이 없습니다.";
"LEGACY_LOGIN_RATE_LIMITED_TITLE" = "요청 제한 가능성 있음 (243)";
"LEGACY_LOGIN_RATE_LIMITED_MESSAGE" = "시도 횟수가 너무 많습니다. 잠시 기다리거나 네트워크/VPN을 변경한 후 다시 시도하세요.\n\n세부 정보:\n%@";
"LEGACY_LOGIN_UNKNOWN_ERROR" = "알 수 없는 오류";
```

- [ ] **Step 3: Apply the Simplified Chinese translations**

Replace the matching Simplified Chinese entries with these exact values:

```text
"CUSTOM_TAB_BAR_GRID_DETAIL" = "轻点项目以添加或移除。拖动下方栏位以调整顺序。";
"PADLOCK_LOCKED_LABEL" = "已锁定";
"UNKNOWN_SOURCE" = "未知来源";
"DOWNLOAD_VIDEO_NUMBER_TITLE" = "视频 %lu";
"UNKNOWN_ERROR" = "发生未知错误。";
"INSTALL_IFONT_BUTTON_TITLE" = "iFont 应用";
"FONT_SYSTEM_DEFAULT_SUBTITLE" = "系统默认";
"LEGACY_LOGIN_INFO_LABEL" = "使用用户名和密码登录。\n\n不支持使用 Google 或 Apple 登录。如果你的账户使用其中一种方式，请先为账户添加密码。";
"LEGACY_LOGIN_MISSING_INPUT_TITLE" = "缺少输入内容";
"LEGACY_LOGIN_MISSING_INPUT_MESSAGE" = "请输入用户名和密码。";
"LEGACY_LOGIN_VERIFYING_STATUS" = "正在验证…";
"LEGACY_LOGIN_SIGNING_IN_STATUS" = "正在登录…";
"LEGACY_LOGIN_UNAVAILABLE_TITLE" = "不可用";
"LEGACY_LOGIN_CLASSES_MISSING_MESSAGE" = "缺少登录类。";
"LEGACY_LOGIN_BUILD_COMMAND_FAILED_MESSAGE" = "无法创建命令。";
"LEGACY_LOGIN_CRASH_AVOIDED_TITLE" = "已避免崩溃";
"LEGACY_LOGIN_UNEXPECTED_RESPONSE_TITLE" = "意外响应";
"LEGACY_LOGIN_NO_TOKEN_NO_CHALLENGE_MESSAGE" = "没有令牌，也没有验证挑战。";
"LEGACY_LOGIN_CHALLENGE_MISSING_INFO_MESSAGE" = "验证挑战缺少请求 ID 或 URL。";
"LEGACY_LOGIN_CHALLENGE_CLASSES_MISSING_MESSAGE" = "缺少验证挑战或主机类。";
"LEGACY_LOGIN_BUILD_CHALLENGE_FAILED_MESSAGE" = "无法创建验证挑战。";
"LEGACY_LOGIN_NO_TOKEN_MESSAGE" = "响应中没有令牌。";
"LEGACY_LOGIN_FAILED_TITLE" = "登录失败";
"LEGACY_LOGIN_NO_ACCOUNT_MESSAGE" = "未返回任何账户。";
"LEGACY_LOGIN_RATE_LIMITED_TITLE" = "可能已受到速率限制（243）";
"LEGACY_LOGIN_RATE_LIMITED_MESSAGE" = "尝试次数过多。请稍候，或切换网络/VPN 后重试。\n\n详细信息：\n%@";
"LEGACY_LOGIN_UNKNOWN_ERROR" = "未知错误";
```

- [ ] **Step 4: Apply the Traditional Chinese translations**

Replace the matching Traditional Chinese entries with these exact values:

```text
"CUSTOM_TAB_BAR_GRID_DETAIL" = "點一下項目即可加入或移除。拖曳下方欄位以調整順序。";
"PADLOCK_LOCKED_LABEL" = "已鎖定";
"UNKNOWN_SOURCE" = "未知來源";
"DOWNLOAD_VIDEO_NUMBER_TITLE" = "影片 %lu";
"UNKNOWN_ERROR" = "發生未知錯誤。";
"INSTALL_IFONT_BUTTON_TITLE" = "iFont App";
"FONT_SYSTEM_DEFAULT_SUBTITLE" = "系統預設";
"LEGACY_LOGIN_INFO_LABEL" = "使用使用者名稱和密碼登入。\n\n不支援使用 Google 或 Apple 登入。如果你的帳號使用其中一種方式，請先為帳號新增密碼。";
"LEGACY_LOGIN_MISSING_INPUT_TITLE" = "缺少輸入內容";
"LEGACY_LOGIN_MISSING_INPUT_MESSAGE" = "請輸入使用者名稱和密碼。";
"LEGACY_LOGIN_VERIFYING_STATUS" = "正在驗證…";
"LEGACY_LOGIN_SIGNING_IN_STATUS" = "正在登入…";
"LEGACY_LOGIN_UNAVAILABLE_TITLE" = "無法使用";
"LEGACY_LOGIN_CLASSES_MISSING_MESSAGE" = "缺少登入類別。";
"LEGACY_LOGIN_BUILD_COMMAND_FAILED_MESSAGE" = "無法建立指令。";
"LEGACY_LOGIN_CRASH_AVOIDED_TITLE" = "已避免閃退";
"LEGACY_LOGIN_UNEXPECTED_RESPONSE_TITLE" = "非預期的回應";
"LEGACY_LOGIN_NO_TOKEN_NO_CHALLENGE_MESSAGE" = "沒有權杖，也沒有驗證挑戰。";
"LEGACY_LOGIN_CHALLENGE_MISSING_INFO_MESSAGE" = "驗證挑戰缺少請求 ID 或 URL。";
"LEGACY_LOGIN_CHALLENGE_CLASSES_MISSING_MESSAGE" = "缺少驗證挑戰或主機類別。";
"LEGACY_LOGIN_BUILD_CHALLENGE_FAILED_MESSAGE" = "無法建立驗證挑戰。";
"LEGACY_LOGIN_NO_TOKEN_MESSAGE" = "回應中沒有權杖。";
"LEGACY_LOGIN_FAILED_TITLE" = "登入失敗";
"LEGACY_LOGIN_NO_ACCOUNT_MESSAGE" = "未傳回任何帳號。";
"LEGACY_LOGIN_RATE_LIMITED_TITLE" = "可能已受到速率限制（243）";
"LEGACY_LOGIN_RATE_LIMITED_MESSAGE" = "嘗試次數過多。請稍候，或切換網路/VPN 後再試一次。\n\n詳細資訊：\n%@";
"LEGACY_LOGIN_UNKNOWN_ERROR" = "未知錯誤";
```

- [ ] **Step 5: Verify this locale batch turns green**

Run:

```powershell
& 'tests\localization\Test-V6Localization.ps1' -Locale ja,ko,zh_CN,zh-Hant
```

Expected: exit code `0` and `V6 localization contract passed: ja, ko, zh_CN, zh-Hant`.

- [ ] **Step 6: Check and commit the East Asian batch**

Run:

```powershell
git diff --check
git add -- "layout/Library/Application Support/BHT/BHTwitter.bundle/ja.lproj/Localizable.strings" "layout/Library/Application Support/BHT/BHTwitter.bundle/ko.lproj/Localizable.strings" "layout/Library/Application Support/BHT/BHTwitter.bundle/zh_CN.lproj/Localizable.strings" "layout/Library/Application Support/BHT/BHTwitter.bundle/zh-Hant.lproj/Localizable.strings"
git commit -m "Translate v6 East Asian localizations"
```

Expected: `git diff --check` exits `0`, then one commit containing only these four locale files.

### Task 6: Run Full Validation And Publish

**Files:**
- Verify: `tests/localization/Test-V6Localization.ps1`
- Verify: `layout/Library/Application Support/BHT/BHTwitter.bundle/*.lproj/Localizable.strings`

- [ ] **Step 1: Run the complete localization contract**

Run:

```powershell
& 'tests\localization\Test-V6Localization.ps1'
```

Expected: exit code `0` and `V6 localization contract passed: ar, de, es, fr, hr, id, ja, ko, pl, ru, sv, tr, uk, zh_CN, zh-Hant`.

- [ ] **Step 2: Verify every localization remains valid UTF-8**

Run:

```powershell
$root = 'layout\Library\Application Support\BHT\BHTwitter.bundle'
$utf8 = [System.Text.UTF8Encoding]::new($false, $true)
$invalid = @(
    Get-ChildItem $root -Directory -Filter '*.lproj' | ForEach-Object {
        $path = Join-Path $_.FullName 'Localizable.strings'
        try {
            [void]$utf8.GetString([System.IO.File]::ReadAllBytes($path))
        } catch {
            $path
        }
    }
)
if ($invalid.Count -gt 0) {
    $invalid | ForEach-Object { Write-Host "Invalid UTF-8: $_" -ForegroundColor Red }
    exit 1
}
Write-Host 'All Localizable.strings files are valid UTF-8.'
```

Expected: exit code `0` and `All Localizable.strings files are valid UTF-8.`

- [ ] **Step 3: Verify the repository diff and commit history**

Run:

```powershell
git diff --check
git status --short --branch
git log --oneline --decorate -6
```

Expected: `git diff --check` exits `0`; the worktree is clean; the branch contains the design, plan, test/first-locale, second-locale, Slavic, and East Asian commits on top of `v6.0.4`.

- [ ] **Step 4: Record the build limitation without changing the patch**

Run:

```powershell
$make = Get-Command make -ErrorAction SilentlyContinue
$wsl = Get-Command wsl -ErrorAction SilentlyContinue
if (-not $make) { Write-Host 'Native make unavailable.' }
if ($wsl) {
    $wslOutput = & wsl -e sh -lc 'command -v make' 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "WSL make: $wslOutput"
    } else {
        Write-Host 'WSL build environment unavailable.'
    }
}
exit 0
```

Expected on the current host: native `make` and the WSL build environment are reported unavailable, while the diagnostic itself exits `0`. Do not claim a Theos build passed; the localization contract, UTF-8 validation, and diff checks are the available verification evidence.

- [ ] **Step 5: Push the completed branch to the user fork**

Run:

```powershell
git push -u origin codex/v6-i18n
```

Expected: `origin/codex/v6-i18n` is created or fast-forwarded to the final local commit, with upstream tracking configured.
