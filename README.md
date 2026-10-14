# سرب — Sirb

[العربية](#العربية) · [English](#english)

## العربية

**سرب** متصفح لأجهزة سطح المكتب مبني باستخدام Flutter وChromium Embedded Framework ‏(CEF)، ومصمم لتصفح الفيديو وإدارة مجموعات كبيرة من علامات التبويب. يدعم Linux وWindows وmacOS، ولا يستهدف الهواتف أو الويب.

### المميزات

- علامات تبويب عمودية مع التثبيت وإعادة الترتيب.
- ملف Chromium دائم للحفاظ على تسجيل الدخول، وحفظ الجلسات وسجل التصفح محليًا باستخدام SQLite.
- البحث عبر DuckDuckGo من شريط العنوان والصفحة الجديدة.
- تصفية طلبات الإعلانات وقواعد خاصة بالمواقع، بما فيها YouTube.
- إدارة استهلاك الموارد عبر إسبات علامات التبويب غير النشطة والتحميل المسبق المحدود، دون إسبات علامات التبويب التي تشغّل الوسائط.
- إعدادات للمعالج والذاكرة وتسريع الرسوميات بحسب إمكانات نظام التشغيل.
- وضع ألعاب وخيار فتح اللعبة في نافذة CEF أصلية داخل سرب.
- واجهة بالعربية والإنجليزية مع دعم اتجاه الكتابة من اليمين إلى اليسار.

### لقطات الشاشة

#### الصفحة الرئيسية

<img width="1920" height="996" alt="الصفحة الرئيسية في سرب" src="https://github.com/user-attachments/assets/5dcfc5f4-7846-44b1-a28a-dbe809e14f6b" />

#### البحث

<img width="1920" height="996" alt="البحث في سرب" src="https://github.com/user-attachments/assets/6cbcefd6-1ba9-4887-b1bf-6180aacf7f30" />

#### الإعدادات

<img width="1920" height="996" alt="إعدادات سرب" src="https://github.com/user-attachments/assets/e2d96a5c-c93c-44f4-9521-7dc1d511327c" />

### التشغيل من المصدر

يتطلب المشروع Flutter بإصدار **3.47 أو أحدث** وDart بإصدار **3.12 أو أحدث وأقل من 4.0**، مع أدوات البناء الخاصة بنظام التشغيل واتصال بالإنترنت لتنزيل الحزم وتوزيعة CEF المحددة في المشروع. تُستخدم نسخة محلية معدّلة من `webview_cef` داخل `third_party/webview_cef`.

```bash
flutter pub get
flutter gen-l10n
```

شغّل الأمر المناسب على نظام التشغيل المستهدف:

```bash
# Linux
flutter run -d linux

# Windows
flutter run -d windows

# macOS
flutter run -d macos
```

راجع [ملاحظات البناء والتشغيل](BUILD_NOTES.md) لمعرفة المتطلبات التفصيلية، وإعداد CocoaPods على macOS، والمعماريات المدعومة، وإنشاء حزم التوزيع. تُحفظ الحزم الناتجة في `dist/` ولا تُضاف إلى Git.

### ملاحظات مهمة

- تختلف ضوابط المعالج والذاكرة واختيار المعالج الرسومي بحسب المنصة؛ لا تتوفر بعض الخيارات على macOS أو داخل Flatpak.
- لا يُضمن دعم H.264/AAC أو Widevine في توزيعات CEF الرسمية، ولا تُضمن إزالة جميع إعلانات YouTube أو دعم جميع تدفقات DRM.
- يتطلب عزل Chromium على Linux مساحات أسماء المستخدم أو بيئة Flatpak/Zypak المناسبة. تكامل عزل CEF غير مفعّل في نسختَي Windows وmacOS الحاليتين؛ راجع ملاحظات البناء قبل التوزيع.
- لا تفعّل خيارات Chromium غير الآمنة للتصفح العام. تُعدّل قواعد حجب الإعلانات فقط في `lib/features/ads/ad_rules.dart`.
- تم التحقق من البناء والتشغيل على Linux x64؛ ما زال التحقق على Windows وmacOS والمعماريات الأخرى يتطلب الأجهزة المناسبة.

### التطوير والتوثيق

```bash
flutter analyze
flutter test
```

- [تعليمات المشروع](PROJECT_NOTES.md): قواعد التطوير وبنية المشروع والفروق بين المنصات؛ تُقرأ كاملة قبل التعديل.
- [قرارات التصميم](DESIGN_DECISIONS.md).
- [نتائج التحقق والقيود](VERIFICATION.md).
- [ملاحظات النسخة المعدّلة من webview_cef](third_party/webview_cef/SIRB_FORK.md).

### الترخيص

المشروع مرخّص بموجب [Apache License 2.0](LICENSE). تخضع التبعيات ومكونات Chromium وCEF لتراخيصها الخاصة.

---

## English

**Sirb** is a desktop browser built with Flutter and Chromium Embedded Framework (CEF), designed for video browsing and large tab collections. It targets Linux, Windows, and macOS, not mobile or web.

### Features

- Vertical tabs with pinning and reordering.
- A persistent Chromium profile to retain logins, with sessions and browsing history stored locally in SQLite.
- DuckDuckGo search from the address bar and new-tab page.
- Ad-request filtering and site-specific rules, including YouTube rules.
- Resource-aware sleeping for inactive tabs and bounded preloading, while protecting media-playing tabs from sleep.
- CPU, memory, and graphics-acceleration settings where supported by the operating system.
- Game mode and an option to open games in a native CEF window within Sirb.
- Arabic and English interfaces with right-to-left layout support.

### Screenshots

#### Home page

<img width="1920" height="996" alt="Sirb home page" src="https://github.com/user-attachments/assets/5dcfc5f4-7846-44b1-a28a-dbe809e14f6b" />

#### Search

<img width="1920" height="996" alt="Search in Sirb" src="https://github.com/user-attachments/assets/6cbcefd6-1ba9-4887-b1bf-6180aacf7f30" />

#### Settings

<img width="1920" height="996" alt="Sirb settings" src="https://github.com/user-attachments/assets/e2d96a5c-c93c-44f4-9521-7dc1d511327c" />

### Run from source

The project requires **Flutter 3.47 or later** and **Dart 3.12 or later, below 4.0**, platform-specific build tools, and internet access to fetch dependencies and the pinned CEF distribution. It uses a local fork of `webview_cef` in `third_party/webview_cef`.

```bash
flutter pub get
flutter gen-l10n
```

Run the matching command on your target operating system:

```bash
# Linux
flutter run -d linux

# Windows
flutter run -d windows

# macOS
flutter run -d macos
```

See [build and runtime notes](BUILD_NOTES.md) for full prerequisites, macOS CocoaPods setup, supported architectures, and packaging instructions. Distribution packages are written to `dist/` and excluded from Git.

### Important notes

- CPU, memory, and GPU controls vary by platform; some options are unavailable on macOS or inside Flatpak.
- Official CEF distributions cannot be assumed to support H.264/AAC or Widevine. Complete YouTube ad removal and support for all DRM streams are not guaranteed.
- Chromium sandboxing on Linux requires user namespaces or the appropriate Flatpak/Zypak environment. CEF sandbox integration is currently disabled on Windows and macOS; review the build notes before distribution.
- Never enable insecure Chromium switches for general browsing. Modify ad-blocking rules only in `lib/features/ads/ad_rules.dart`.
- Build and runtime verification has been completed on Linux x64; Windows, macOS, and other architectures still require verification on suitable hosts.

### Development and documentation

```bash
flutter analyze
flutter test
```

- [Project notes](PROJECT_NOTES.md): binding development rules, project structure, and platform differences; read in full before making changes.
- [Design decisions](DESIGN_DECISIONS.md).
- [Verification results and limitations](VERIFICATION.md).
- [webview_cef fork notes](third_party/webview_cef/SIRB_FORK.md).

### License

The project is licensed under the [Apache License 2.0](LICENSE). Dependencies and Chromium/CEF components retain their own licenses.
