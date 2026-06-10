// Stellar Download Manager
// Copyright (C) 2026 Ninka_
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

pragma Singleton
import QtQuick

// Single source of truth for the UI language list. Each entry: { code, display }.
// display = "English name - Native name". Native names are stored UTF-8.
QtObject {
    readonly property var entries: [
        { code: "",        display: "English" },
        { code: "sq",      display: "Albanian - Shqip" },
        { code: "am",      display: "Amharic - አማርኛ" },
        { code: "ar",      display: "Arabic - العربية" },
        { code: "hy",      display: "Armenian - Հայերեն" },
        { code: "az",      display: "Azerbaijani - Azərbaycan dili" },
        { code: "be",      display: "Belarusian - Беларуская" },
        { code: "bn",      display: "Bengali - বাংলা" },
        { code: "bs",      display: "Bosnian - Bosanski" },
        { code: "bg",      display: "Bulgarian - Български" },
        { code: "my",      display: "Burmese - မြန်မာ" },
        { code: "ca",      display: "Catalan - Català" },
        { code: "zh_CN",   display: "Chinese (Simplified) - 简体中文" },
        { code: "zh_TW",   display: "Chinese (Traditional) - 繁體中文" },
        { code: "hr",      display: "Croatian - Hrvatski" },
        { code: "cs",      display: "Czech - Čeština" },
        { code: "da",      display: "Danish - Dansk" },
        { code: "nl",      display: "Dutch - Nederlands" },
        { code: "nl_BE",   display: "Dutch (Belgium) - Nederlands (België)" },
        { code: "et",      display: "Estonian - Eesti" },
        { code: "fa",      display: "Farsi (Persian) - فارسی" },
        { code: "fil",     display: "Filipino - Filipino" },
        { code: "fi",      display: "Finnish - Suomi" },
        { code: "fr",      display: "French - Français" },
        { code: "gl",      display: "Galician - Galego" },
        { code: "ka",      display: "Georgian - ქართული" },
        { code: "de",      display: "German - Deutsch" },
        { code: "el",      display: "Greek - Ελληνικά" },
        { code: "gu",      display: "Gujarati - ગુજરાતી" },
        { code: "ha",      display: "Hausa - Hausa" },
        { code: "he",      display: "Hebrew - עברית" },
        { code: "hi",      display: "Hindi - हिन्दी" },
        { code: "hu",      display: "Hungarian - Magyar" },
        { code: "ig",      display: "Igbo - Igbo" },
        { code: "id",      display: "Indonesian - Bahasa Indonesia" },
        { code: "ga",      display: "Irish - Gaeilge" },
        { code: "it",      display: "Italian - Italiano" },
        { code: "ja",      display: "Japanese - 日本語" },
        { code: "jv",      display: "Javanese - Basa Jawa" },
        { code: "kn",      display: "Kannada - ಕನ್ನಡ" },
        { code: "km",      display: "Khmer - ខ្មែរ" },
        { code: "ko",      display: "Korean - 한국어" },
        { code: "lo",      display: "Lao - ລາວ" },
        { code: "lv",      display: "Latvian - Latviešu" },
        { code: "lt",      display: "Lithuanian - Lietuvių" },
        { code: "mk",      display: "Macedonian - Македонски" },
        { code: "ml",      display: "Malayalam - മലയാളം" },
        { code: "ms",      display: "Malay - Bahasa Melayu" },
        { code: "mr",      display: "Marathi - मराठी" },
        { code: "mn",      display: "Mongolian - Монгол" },
        { code: "ne",      display: "Nepali - नेपाली" },
        { code: "nb",      display: "Norwegian - Norsk Bokmål" },
        { code: "ps",      display: "Pashto - پښتو" },
        { code: "pl",      display: "Polish - Polski" },
        { code: "pt",      display: "Portuguese - Português" },
        { code: "pt_BR",   display: "Portuguese (Brazilian) - Português (Brasil)" },
        { code: "pa",      display: "Punjabi - ਪੰਜਾਬੀ" },
        { code: "ro",      display: "Romanian - Română" },
        { code: "ru",      display: "Russian - Русский" },
        { code: "sr_Cyrl", display: "Serbian (Cyrillic) - Српски" },
        { code: "sr_Latn", display: "Serbian (Latin) - Srpski" },
        { code: "si",      display: "Sinhala - සිංහල" },
        { code: "sk",      display: "Slovak - Slovenčina" },
        { code: "sl",      display: "Slovenian - Slovenščina" },
        { code: "es",      display: "Spanish - Español" },
        { code: "sw",      display: "Swahili - Kiswahili" },
        { code: "sv",      display: "Swedish - Svenska" },
        { code: "ta",      display: "Tamil - தமிழ்" },
        { code: "te",      display: "Telugu - తెలుగు" },
        { code: "th",      display: "Thai - ไทย" },
        { code: "tr",      display: "Turkish - Türkçe" },
        { code: "uk",      display: "Ukrainian - Українська" },
        { code: "ur",      display: "Urdu - اردو" },
        { code: "ug",      display: "Uyghur - ئۇيغۇرچە" },
        { code: "uz",      display: "Uzbek - Oʻzbek" },
        { code: "vi",      display: "Vietnamese - Tiếng Việt" },
        { code: "cy",      display: "Welsh - Cymraeg" },
        { code: "yo",      display: "Yoruba - Yorùbá" }
    ]

    // Display string for a code (falls back to English).
    function displayForCode(code) {
        for (var i = 0; i < entries.length; ++i)
            if (entries[i].code === code)
                return entries[i].display
        return entries[0].display
    }
}
