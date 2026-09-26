# Windows localization

Localization controls two separate choices. Text and general number formats use the app language selected by the user, while dates and times follow the user's Windows region and time zone.

## Define the supported languages in one place

The Windows client supports the following BCP 47 language tags.

| Tag | Language |
| --- | --- |
| `bg-BG` | Bulgarian |
| `cs-CZ` | Czech |
| `de-DE` | German |
| `en-US` | English |
| `es-ES` | Spanish |
| `fr-FR` | French |
| `he-IL` | Hebrew |
| `it-IT` | Italian |
| `ja-JP` | Japanese |
| `ko-KR` | Korean |
| `nl-BE` | Dutch (Belgium) |
| `nl-NL` | Dutch (Netherlands) |
| `pl-PL` | Polish |
| `pt-BR` | Portuguese (Brazil) |
| `pt-PT` | Portuguese (Portugal) |
| `ro-RO` | Romanian |
| `ru-RU` | Russian |
| `sr-Cyrl-RS` | Serbian (Cyrillic) |
| `sr-Latn-RS` | Serbian (Latin) |
| `tr-TR` | Turkish |
| `uk-UA` | Ukrainian |
| `zh-CN` | Simplified Chinese |
| `zh-TW` | Traditional Chinese |

The default language is `ko-KR`. `I18n.SupportedLanguages` owns the supported set, and the `SIDEY_LANGUAGE` environment variable carries the selected language at runtime.
Selecting Hebrew also changes the WinUI reading direction to right to left. The installer language list is maintained separately from the app catalogs, so a language not offered by Setup can still be selected in the app after installation.

## Store user-facing text in catalogs

Translation files are stored at `src/Sidey.App/Langs/<language tag>.json`. Nested JSON keys are read as a single dot-separated key.

```json
{
  "connection": {
    "retry": "Reconnect"
  }
}
```

```csharp
string label = I18n.Get("connection.retry");
```

Hard-coded user-facing text is easy to miss when adding a language. Catalog keys let tests compare the structure of every language file.

Use `I18n.Format()` for sentences that interpolate values.

```json
{
  "room": {
    "memberCount": "{0} members"
  }
}
```

```csharp
string text = I18n.Format("room.memberCount", memberCount);
```

Word order varies by language. Keep a complete sentence in one catalog value and insert values with placeholders instead of joining several small keys.

## Name keys for meaning and context

Names such as `button1` and `blueText` stop making sense when the layout changes. `connection.retry` describes the text's meaning and where it is used.

- Reuse an existing key when both meaning and context are the same.
- Use separate keys when the contexts differ, even if the Korean text is identical.
- Do not include a specific language or current screen position in a key name.
- Accessibility names and error guidance are user-facing text, so manage them in catalogs too.

## Update every catalog together

A key added to only one file can appear as an empty string or as the key name itself in another language. `LanguageCatalogParityTests` checks:

- every catalog contains the same keys;
- no value is empty;
- placeholder numbers match the reference language; and
- non-Korean catalogs contain no remaining Korean text.

When adding text, update every supported language file in the same change and run this test. Do not copy Korean source text into another language catalog while waiting for a translation. Provide an accurate translation or defer the feature change.

## Use system settings for dates and app settings for numbers

Dates and times follow the user's system locale and time zone because one instant can fall on different dates in different places. Keep server and log values in UTC, then convert them to local time for display.

General numbers and translated formats within the application follow the selected app language. Use an invariant culture or an explicit format for machine-readable data such as sort keys and protocol values.

## Adding a language touches the whole client

When adding a language, verify that every location below understands the same tag:

1. `I18n.SupportedLanguages` and the default-selection rules
2. `Langs/<tag>.json`
3. Launcher language forwarding and mapping
4. Installer language selection and guidance when the installer is also gaining that language
5. Rules that include the catalog in build and publish output
6. `LanguageCatalogParityTests` and deployment checks

Missing the app catalog, launcher mapping, or publish rule can prevent the selected language from applying or leave the published app unable to find its catalog. When the installer also gains a language, update its language contract and tests in the same change.

## Check the running app after the tests pass

After automated tests pass, verify the following in the running app:

- text on first launch, the main window, composer, history, settings, and notification area;
- whether long translations are clipped or push buttons out of place;
- whether any placeholders remain visible;
- whether the selected language persists after restarting the application;
- whether the language selected by the installer reaches the first launch; and
- whether dates and times match the Windows region and time zone.
