## 0. عقد التنفيذ (إلزامي)

- نفّذ المشروع كاملًا الآن. **Do NOT produce an implementation plan** ولا ملخص نوايا ولا أسئلة استيضاحية.
- اكتب كل سطر من كل ملف بشكل كامل وقابل للتشغيل. ممنوع `TODO` وممنوع placeholders وممنوع عبارات مثل "باقي الملفات مشابهة".
- لو فيه غموض: اتخذ أفضل افتراض معقول، دوّنه في `PROJECT_NOTES.md`، وكمّل.
- الاستثناء الوحيد: `DESIGN_DECISIONS.md` (القسم 5) ملف قصير يُكتب أولًا، ثم تكمل التنفيذ مباشرة بدون توقف.
- **القالب ثابت:** لا تحذف ولا تخفف ولا تعدّل أي قاعدة في هذا الملف لتناسب الفكرة. الفكرة تحدد فقط: نمط الواجهة (قسم 5)، الـ features الإضافية (قسم 6)، الأيقونة واللون المميز (قسمان 4 و9)، الميزات المتاحة لكل منصة (قسم 10)، والمهارات الخاصة (قسم 14). أي تعارض ظاهري بين قاعدة والفكرة: التزم بالقاعدة ودوّن التعارض في `PROJECT_NOTES.md` (باستثناء ما ينص عليه قسم 10 عن الميزات غير الممكنة).

### عقد التنفيذ الصارم (STRICT EXECUTION CONTRACT)

This file is a specification to be EXECUTED, not a proposal to be discussed. Read it completely (first line to last line), then implement it literally.

1. **Do NOT produce an implementation plan**, roadmap, outline, architecture summary, or any "here is what I will do" message. Your first action must be a tool call (create a file / run a command), not prose. The only file allowed before the code is `DESIGN_DECISIONS.md` (section 5).
2. **Do NOT ask for confirmation or permission at any point** ("should I proceed?", "shall I execute?", "do you want me to...?"). The answer is always: yes, execute everything in this file, now.
3. **Do NOT stop, pause, or hand control back** until the definition of done (section 15) is fully met. An error is NOT a reason to stop or ask: read the error, fix the root cause, re-run, continue. Only a truly unresolvable external blocker (e.g. missing SDK/hardware on this machine) may be reported, and only after everything else is implemented, with the exact blocker written to `PROJECT_NOTES.md` / `BUILD_NOTES.md`.
4. **Every requirement in this file is binding**: every sentence with an imperative, "must", "يجب", "ممنوع", "إلزامي", every table row, every list item, every file name, every folder name, every variable. Do not skip, merge, shorten, reinterpret, reorder by preference, or "improve" any of them. If you believe a requirement is wrong, implement it anyway and write your objection in `PROJECT_NOTES.md`.
5. **Do NOT edit, rewrite, rename, shorten, or "tidy up" this specification file.** It is read-only input. Create the project files only.
6. **No partial work:** no `TODO`, no placeholders, no stubs, no mock/fake implementations, no "similar to above", no "..." or commented-out code standing in for real code, no replacing a hard requirement with an easier one. Every file is written in full.
7. **Work in order, section 1 → 15.** For each section, create every file it requires before moving to the next one. Do not leave a section "for later".
8. **Final verification loop (mandatory before you finish):** (a) run `flutter analyze` and fix every issue; (b) run whatever builds/tests can run on this machine and fix failures; (c) re-read this file from top to bottom and, for each requirement, confirm it exists in the code (file path + what implements it); (d) implement anything missing and repeat (c) until nothing is missing.
9. **Final message = a short report only:** a table `requirement → file(s) → status` where status is `done` or `disabled on <platform>: <reason>`. No plan, no questions, no marketing.

---

## فكرة المشروع

متصفح ويب **لسطح المكتب فقط** (Windows وLinux وmacOS) مبني بـ Flutter، موجّه لمشاهدة الفيديوهات (YouTube أولًا) وفتح عدد كبير من التبويبات في نفس الوقت بدون بطء أو تقطيع. المشكلة التي يحلها: متصفحات مثل Brave تبدأ تبطؤ عند فتح نحو 35 صفحة حتى على جهاز قوي (كرت شاشة منفصل + 64 GB RAM)، لأن العتاد لا يُستغل جيدًا وإدارة التبويبات ضعيفة. فالتطبيق يعطي المستخدم تحكمًا حقيقيًا بالموارد (CPU/RAM/GPU)، وإدارة ذكية للتبويبات، وتحميلًا مسبقًا يسرّع التنقل، وحاجب إعلانات مدمجًا يركز على مواقع الفيديو.

المطلوب **متصفح يعمل فعلًا** وليس واجهة تشبه متصفحًا: يفتح المواقع الحقيقية، يشغّل YouTube بصوت وملء شاشة سليمين، ويحفظ تسجيل الدخول والكوكيز والكاش بين التشغيلات (profile دائم في مجلد بيانات التطبيق).

### 1. محرك العرض (قرار تقني إلزامي)

- محرك Chromium حقيقي مضمّن داخل Flutter عبر Texture. المرشح الأول: `webview_cef` (مبني على CEF ويدعم Windows وmacOS وLinux). تحقق من أحدث إصدار على pub.dev ومن دعمه للمنصات الثلاث قبل الاعتماد عليه، واختر الحزمة الأنسب لأهداف هذا التطبيق. ممنوع: `iframe`، أو فتح المتصفح الخارجي، أو WebView مزيّف، أو أي حزمة لا تدعم سطح المكتب الثلاث.
- يجب أن يتيح المحرك: تمرير command-line switches وenv قبل الإطلاق، واعتراض الطلبات وإلغاءها (للحاجب)، وحقن CSS/JS عند بدء تحميل المستند، وعدة browser instances مستقلة (instance لكل تبويب)، وإخفاء/إظهار instance (`WasHidden`)، وإغلاق instance وإعادة إنشائه، ومعرفة أن التبويب يشغّل صوتًا، والتنزيلات، وملء شاشة الفيديو.
- إذا لم تكشف الحزمة شيئًا من هذه عبر Dart: اعمل fork داخل `third_party/` وأضف الكود الأصلي (C++/Obj-C++) المطلوب بدل إسقاط الميزة، ودوّن ذلك في `PROJECT_NOTES.md`.
- اختبر فعليًا تشغيل YouTube (VP9/AV1/Opus) وبثًا HLS بـ H.264/AAC. ملفات CEF الجاهزة الرسمية قد لا تتضمن الكودكات المسجّلة (H.264/AAC)؛ إن كان الأمر كذلك وثّقه في `PROJECT_NOTES.md` مع الحل الممكن، ولا تدّعي دعمًا غير موجود.
- على Linux: قرار الـ sandbox (chrome-sandbox / user namespaces) داخل AppImage وFlatpak (مثل zypak) يجب أن يعمل فعلًا ويُوثَّق في `BUILD_NOTES.md`.

### 2. شريط العنوان والبحث

- محرك البحث الافتراضي **DuckDuckGo**: أي نص ليس رابطًا صحيحًا يُبحث عنه. في الإعدادات قائمة لتغيير المحرك (Google، Bing، Brave Search، Startpage).
- أزرار: رجوع، تقدّم، إعادة تحميل/إيقاف، الرئيسية. اقتراحات من السجل أثناء الكتابة. بحث داخل الصفحة، تكبير/تصغير، قائمة تنزيلات بسيطة.
- اختصارات: `Ctrl+T` تبويب جديد، `Ctrl+W` إغلاق، `Ctrl+Shift+T` استرجاع آخر مغلق، `Ctrl+L` العنوان، `Ctrl+F` بحث، `Ctrl+R` إعادة تحميل، `Ctrl+Tab` التبديل، `Ctrl+1..9`، `F11` ملء الشاشة (وعلى macOS `Cmd` بدل `Ctrl`).
- صفحة التبويب الجديد: مربع بحث DuckDuckGo + أكثر المواقع زيارة من السجل (كل النصوص من ARB).

### 3. التبويبات

- عدد كبير جدًا (اختبر 100 تبويب). يُقترح شريط تبويبات **رأسي** قابل للطي لأن الأفقي يضيق بعد ~20 تبويبًا (القرار النهائي في `DESIGN_DECISIONS.md`): أيقونة + عنوان، بحث داخل التبويبات، تثبيت، سحب لإعادة الترتيب، كتم الصوت، تكرار، إغلاق (الأخرى / ما بعده)، مؤشر واضح للتبويب النائم.
- حالات التبويب: **حي** (النشط)، **خلفي مُخفَّف** (يُخفى ويتوقف رسمه لكن يحتفظ بحالته)، **نائم** (instance مغلق، يحتفظ بالرابط والعنوان والأيقونة وموضع الفيديو إن أمكن، ويُعاد تحميله عند الضغط عليه).
- التبويب الذي يشغّل صوتًا/فيديو **لا يُنام ولا يُخنق أبدًا**.
- النوم التلقائي: بعد مدة خمول قابلة للضبط (الافتراضي 10 دقائق، أو إيقافه)، وعند اقتراب الاستهلاك من حد RAM (القسم 5) ينام الأقدم استخدامًا أولًا. وحد أقصى لعدد التبويبات الحية (قابل للضبط).
- **التحميل المسبق:** preconnect وDNS-prefetch لنطاقات الفيديو الشائعة، وعند وقوف الماوس على رابط أو صورة مصغرة لفيديو نحو 300ms يُحمَّل مسبقًا في instance مخفي بعدد محدود (الافتراضي 2 متزامنة)، فإن فتحه المستخدم استُخدم فورًا، وإلا أُهمل بعد مهلة. قابل للتعطيل، ولا يتجاوز حدود الموارد.

### 4. السجلات واستعادة الجلسة

- **سجل الصفحات:** عنوان/رابط/وقت/أيقونة، بحث، حذف عنصر أو نطاق زمني أو الكل.
- **سجل التبويبات:** كل إغلاق يُحفظ كعملية واحدة (تبويب واحد، أو مجموعة عند «إغلاق الأخرى/الكل»، أو إغلاق التطبيق) مع وقتها وعدد تبويباتها. لكل عملية زر **«استرجاع»** يعيد كل تبويباتها بترتيبها. مثال: فتحت 5 تبويبات وأغلقتها ← أفتح سجل التبويبات ← «استرجاع» ← ترجع الخمسة كلها. ويمكن أيضًا استرجاع تبويب واحد منها.
- **عند إغلاق التطبيق أو إعادة تشغيل الجهاز أو انهياره:** خيار في الإعدادات لسلوك البدء: صفحة جديدة / استعادة آخر جلسة تلقائيًا / اسأل. الجلسة تُحفظ باستمرار (عند أي تغيير في التبويبات وكل بضع ثوانٍ)، وليس عند الإغلاق فقط، حتى تنجو من الانهيار وإطفاء الجهاز المفاجئ.
- التخزين: قاعدة محلية موثوقة (SQLite عبر `sqflite_common_ffi` أو `drift`، حسب اختيارك) في مجلد بيانات التطبيق.

### 5. شاشة «الأداء» في الإعدادات

القاعدة العامة: كل خيار يُنفَّذ فعليًا عبر آلية النظام. وإن تعذّر على منصة ما يُعطَّل بوضوح برسالة مترجمة (حسب قسم 10)، ولا يُزيَّف.

- تعرض الشاشة الجهاز المكتشف: عدد الأنوية، RAM، الكروت (منفصل/مدمج)، واستهلاك التطبيق الحالي.
- **أقصى عدد أنوية CPU** (من 1 إلى عدد الأنوية، أو بدون حد): Windows ← `SetProcessAffinityMask` أو Job Object؛ Linux ← `sched_setaffinity` عبر `dart:ffi` (أو `taskset` عند الإطلاق)؛ وتنتقل للعمليات الفرعية للمحرك. macOS لا يدعم affinity: عطّل الخيار برسالة.
- **أقصى RAM** (بدون حد / قيمة بالـ GB): حد صارم حيثما أمكن (Windows ← Job Object؛ Linux ← cgroup v2 عبر `systemd-run --user --scope -p MemoryMax=` عند الإطلاق)، وحد ناعم على كل المنصات عبر نوم التبويبات قبل بلوغه (عند ~85%).
- **كرت الشاشة:** تلقائي / المنفصل / المدمج، ومعه مفتاح تسريع الأجهزة (GPU acceleration) تشغيل/إيقاف. Linux ← `DRI_PRIME` و`__NV_PRIME_RENDER_OFFLOAD` و`__GLX_VENDOR_LIBRARY_NAME`؛ Windows ← تفضيل GPU لملف التطبيق التنفيذي في `HKCU\Software\Microsoft\DirectX\UserGpuPreferences` (أو آلية موثقة أفضل بعد التحقق)؛ macOS ← عطّل اختيار الكرت (يديره النظام).
- كذلك: مهلة نوم التبويبات الخاملة، حد التبويبات الحية، تفعيل/تعطيل التحميل المسبق.
- تغييرات CPU/RAM/GPU تتطلب إعادة تشغيل التطبيق (لأن flags وenv تُحدَّد عند الإطلاق): زر **«طبّق وأعد التشغيل»** يعيد تشغيل التطبيق ذاتيًا ويستعيد الجلسة تلقائيًا.

### 6. حاجب الإعلانات (مجلد `ads`)

- مدمج، مفعّل افتراضيًا، يركز على مواقع مشاهدة الفيديو: YouTube أولًا (إعلانات الفيديو قبل/أثناء التشغيل، overlay، banners، البطاقات الترويجية في الصفحة الرئيسية ونتائج البحث)، ثم مواقع الفيديو الشائعة الأخرى.
- ثلاث طبقات: (أ) حجب الطلبات (نطاقات + أنماط URL) على مستوى المحرك قبل خروج الطلب؛ (ب) إخفاء العناصر الإعلانية بـ CSS (عام + لكل موقع)؛ (ج) سكربت خاص بـ YouTube للتعامل مع إعلانات المشغّل، يُحقن عند document-start.
- **كل القواعد في ملف واحد مستقل داخل مجلد `ads`:** `lib/features/ads/ad_rules.dart`، ثوابت Dart فقط بدون أي منطق: `blockedDomains`، `blockedUrlPatterns`، `allowedDomains`، `cosmeticSelectorsGlobal`، `cosmeticSelectorsBySite`، `youtubeScripts`. في أعلاه تعليقات بالعربية تشرح كيف يضيف المستخدم قاعدة جديدة. منطق التنفيذ في `lib/features/ads/services/` ويقرأ من هذا الملف فقط، حتى أعدّل القواعد مستقبلًا دون لمس باقي الكود.
- زر في شريط العنوان لتعطيل الحاجب على الموقع الحالي (allowlist محفوظة) مع عدّاد الإعلانات المحجوبة في الصفحة، وخيار تشغيل/إيقاف عام في الإعدادات.
- YouTube يغيّر آلياته باستمرار: اجعل السكربت دفاعيًا (لا ينهار إن تغيّر الـ DOM) ووثّق في `PROJECT_NOTES.md` كيف تُحدَّث القواعد.

### 7. الواجهة وتسلسل الصفحات

- «الواجهة الرئيسية» (الخطوة 4 في قسم 3) هي **المتصفح نفسه** (شريط التبويبات + شريط العنوان + منطقة الويب)، وليست شاشة بطاقات. الإعدادات واصلة منه، وأقسامها: عام (اللغة، الثيم، محرك البحث، سلوك البدء)، الأداء، الحاجب، الخصوصية والبيانات (مسح السجل والكوكيز والكاش)، وقسم المطور آخرًا.
- الثيم يُطبَّق على واجهة التطبيق، ومحتوى الويب يتبع `prefers-color-scheme` حيث يدعمه المحرك.
- الشاشات في `screens/desktop` فقط (TARGETS = desktop).

### 8. معيار نجاح الفكرة (إضافة إلى قسم 15)

- فتح 50 تبويبًا (منها 5 على YouTube فعليًا) والتطبيق يبقى سلسًا، والخاملة تنام تلقائيًا وتُستعاد عند الضغط.
- YouTube يعمل بدون إعلانات الفيديو المعتادة، والصوت وملء الشاشة سليمان.
- سجل التبويبات وجلسة آخر تشغيل يُستعادان حتى بعد إنهاء التطبيق قسرًا (kill).
- خيارات CPU/RAM/GPU مطبّقة فعليًا على Windows وLinux، ومعطّلة بوضوح (غير مزيّفة) حيثما تعذّرت.

---

## 1. المشروع

| المتغير | القيمة |
|---|---|
| APP_NAME | `Sirb` (سرب) |
| APP_ID (reverse-DNS) | `com.h.sirb` |
| LANGUAGES | `ar`, `en` |
| TARGETS | `desktop` |
| UI_PATTERN | `auto` |

- فكرة التطبيق هي نص قسم «فكرة المشروع» أعلاه، وهي المرجع الوحيد للفكرة.
- أي قيمة بقيت `{{...}}` بدون تعبئة = استخدم الافتراضي المكتوب أمامها. وإذا بقي `APP_NAME` أو `APP_ID` فارغًا، اختر اسمًا قصيرًا يناسب الفكرة، و`APP_ID` بصيغة `com.h.<الاسم_المختصر_بحروف_صغيرة>`، ودوّنهما في `PROJECT_NOTES.md`. نفس الـ `APP_ID` يُستخدم في كل مكان (Flatpak، bundle id، الحزم).

**TARGETS** (الافتراضي `all`): القيمة `all`، أو واحدة أو أكثر من `desktop` و`mobile` و`web` (عند الجمع تُدمج الصفوف):

| القيمة | مجلدات `screens/` | المنصات المطلوبة |
|---|---|---|
| desktop | desktop | Windows، Linux، macOS، Flatpak |
| mobile | mobile | Android، iOS |
| web | web | Web |

عند اختيار أقل من `all`: لا تُنشئ المجلدات والمنصات غير المطلوبة (ولا مجلدات `platform/` الخاصة بها)، ولا تحاول بناءها، وتُطبَّق باقي القواعد كما هي على ما بقي.

---

## 2. تعدد اللغات

- استخدم `flutter gen-l10n` مع ملفات ARB لكل لغة في `LANGUAGES`.
- الاتجاه (RTL/LTR) يتبدل تلقائيًا حسب اللغة المختارة.
- **كل** نص ظاهر للمستخدم يجي من ARB، بما فيه الإعدادات وعناوين قسم المطور. ممنوع أي نص ثابت داخل الـ widgets.
- لغة البداية = لغة النظام إن كانت مدعومة، وإلا `en`. اختيار المستخدم يُحفظ ويُطبّق فورًا.

---

## 3. تسلسل الصفحات

1. **شاشة البداية/التعريف:** أيقونة التطبيق + تعريف قصير بالتطبيق.
2. **اختيار اللغة.**
3. **اختيار الثيم:** داكن / نهاري / تلقائي (حسب النظام).
4. **الواجهة الرئيسية:** بسيطة ومرتبة، كل خيار يُعرف مكانه بدون زحام، والإعدادات واصلة منها.

الحفظ بـ `shared_preferences`: اللغة، الثيم، وعلم `onboarding_done`. إذا كان العلم true يُتخطى التسلسل (1–3) في التشغيلات التالية. يظهر خيار تغيير اللغة والثيم لاحقًا من الإعدادات.

---

## 4. الثيم والألوان

| | الخلفية | الأيقونات والأزرار |
|---|---|---|
| داكن | `#212327` | `#232627` |
| نهاري | `#efeef1` | `#fefefe` |

- لون الأزرار في الداكن قريب جدًا من الخلفية، فميّزه بحد 1px بشفافية خفيفة (أبيض 8%) أو ظل ناعم. في النهاري استخدم حدًا/ظلًا أسود خفيفًا (6%).
- لون النص الأساسي: داكن `#CDCCCA`، نهاري `#212327`.
- لون مميز واحد (accent) مشتق من أيقونة التطبيق، يُستخدم باعتدال.
- كل الألوان تُعرَّف في `core/theme` فقط عبر `ThemeData`/`ColorScheme`. ممنوع `Color(0x...)` داخل الـ widgets.

---

## 5. نمط الواجهة (UI/UX)

قبل كتابة أي واجهة، حلّل فكرة التطبيق وطريقة استخدامه، ثم اختر **أنسب نمط UI/UX لفكرة المشروع نفسها**، ولا تستخدم قالبًا جاهزًا.

- **إذا كانت `UI_PATTERN` غير `auto`:** استخدم النمط المحدد كما هو، واكتب في `DESIGN_DECISIONS.md` كيف يُكيَّف لكل منصة.
- **إذا كانت `auto`:** لا يوجد نمط افتراضي ولا نمط ممنوع. كل نمط مقبول **فقط** إذا طابق فكرة التطبيق وطريقة استخدامه، ولا يُختار لمجرد أنه الأكثر شيوعًا.
- أنماط ممكنة (أمثلة وليست حصرًا): Sidebar، Centered Launcher / Task Hub (بطاقات مهام في منتصف الشاشة)، Canvas/Workspace، Split View، Command/Prompt، Conversational، AI-First، Copilot، Floating AI، Contextual/Adaptive، Spatial/Radial، أو أي نمط حديث أنسب.
- **إذا كان الذكاء الاصطناعي جزءًا من التطبيق:** اجعله أساسيًا في التجربة وليس نافذة محادثة مضافة لواجهة تقليدية.

اكتب إجابات الأسئلة التالية في `DESIGN_DECISIONS.md` (سطر أو سطرين لكل سؤال) **قبل** أي كود واجهة:

1. ما أهم إجراء يريد المستخدم القيام به؟
2. ما دور الذكاء الاصطناعي في التطبيق (أو لا دور له)؟
3. ما المعلومات التي تظهر دائمًا؟
4. ما العناصر التي تظهر عند الحاجة فقط؟
5. ما النمط المختار ولماذا؟ (إذا `auto`: اذكر نمطين رفضتهما وسبب رفض كل منهما)
6. كيف يُكيَّف النمط لكل من mobile وdesktop وweb؟

المتطلبات (تنطبق على أي نمط):

- بسيطة ومرتبة، حديثة واحترافية، تسلسل بصري واضح، الوظيفة الأساسية واضحة مباشرة، بلا عناصر لمجرد أنها شائعة.
- الهوية البصرية موحدة بين المنصات، لكن لكل منصة تخطيط وتفاعل يناسبها (ليست نسخًا متطابقة).
- المحتوى المركزي على سطح المكتب والويب له حد أقصى للعرض.
- شبكات البطاقات تتوزع بالتساوي بـ `Wrap`/Grid، بدون بطاقة يتيمة في صف لوحدها وفراغ بجانبها.
- لا يتكرر نفس الإجراء في أكثر من مكان على الشاشة (مثل الإعدادات في الهيدر وفي بطاقة).

---

## 6. هيكل المجلدات

```
lib/
├── core/                  # ثوابت وأساسيات مشتركة
│   ├── theme/             # كل الألوان و ThemeData
│   ├── l10n/              # إعدادات الترجمة (ARB في l10n/ بجذر المشروع حسب gen-l10n)
│   └── constants/         # بينها developer_info.dart
├── shared/                # يُستخدم فعليًا من أكثر من feature
│   ├── models/
│   ├── services/          # contracts مشتركة فعلًا
│   └── widgets/
├── features/
│   ├── onboarding/        # models / services / widgets
│   ├── home/              # models / services / widgets
│   └── settings/          # models / services / widgets
├── platform/              # implementations فقط، ممنوع أي abstract class
│   ├── android/  ├── ios/  ├── linux/  ├── macos/  ├── windows/  └── web/
├── screens/
│   ├── mobile/
│   ├── desktop/
│   └── web/
└── main.dart
```

- أي interface يستخدمه feature واحد فقط → `features/<feature>/services/`. إذا صار يستخدمه أكثر من feature → انقله إلى `shared/services/`.
- أضف features جديدة حسب فكرة التطبيق بنفس البنية.
- **اختيار الشاشات:** المنصة تحدد المجلد (`kIsWeb` → web، Windows/Linux/macOS → desktop، Android/iOS → mobile)، و`LayoutBuilder` يتكيف داخل المجلد مع العرض (مثل متصفح الجوال أو نافذة ضيقة).

---

## 7. قواعد التجاوب (كل الشاشات، كل المنصات)

- `LayoutBuilder` لأي قياس/تخطيط محلي داخل widget (يمنع overflow)، مع `Flexible` و`Expanded` و`Wrap`.
- ممنوع `MediaQuery.of(context).size` إطلاقًا. استخدم `MediaQuery.sizeOf(context)` فقط عند قرار يحتاج حجم نافذة التطبيق كاملة (مثل تبديل نمط تنقل عام).
- **سطح المكتب فقط (Windows/Linux/macOS):** `window_manager` + `setMinimumSize` (الافتراضي 800×600 ما لم تحتج الواجهة أكثر).

---

## 8. الإعدادات وقسم المطور

- الإعدادات تحتوي اللغة والثيم وغيرها حسب التطبيق.
- **قسم المطور يكون آخر شيء في شاشة الإعدادات على جميع المنصات.**
- العنوان والتسميات من ARB. الاسم والبريد والرابط ثوابت في `core/constants/developer_info.dart`:
  - الاسم: `حسام حسن مجرشي` (نفسه في كل اللغات)
  - البريد: `Hossam.Majrashi@gmail.com`
  - الموقع: `https://hossam-majrashi.github.io/Works/`
- المطلوب تنفيذ `_buildContactItem` و`_launchUrl` كاملتين (باستخدام `url_launcher`، وSnackBar عند فشل الفتح). المرجع:

```dart
Text(
  DeveloperInfo.name,
  style: TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w900,
    color: Theme.of(context).colorScheme.onSurface,
  ),
),
const SizedBox(height: 16),
_buildContactItem(
  context,
  icon: Icons.alternate_email_rounded,
  label: l10n.email,
  value: DeveloperInfo.email,
  onTap: () => _launchUrl('mailto:${DeveloperInfo.email}'),
),
const SizedBox(height: 16),
_buildContactItem(
  context,
  icon: Icons.public_rounded,
  label: l10n.website,
  value: 'hossam-majrashi.github.io/Works/',
  onTap: () => _launchUrl(DeveloperInfo.websiteUrl),
),
```

---

## 9. أيقونة التطبيق

- صمّم أيقونة تعبّر عن فكرة المشروع: مصدر SVG ثم PNG بحجم 1024×1024 في `assets/icon/`، مع نسخة foreground للـ adaptive icon (المحتوى داخل المنطقة الآمنة ~66%) ولون خلفية.
- اربطها بالمشروع عبر **`icons_launcher` بالإصدار 3.1.0 بالضبط** (dev_dependency + إعداده في `pubspec.yaml` حسب توثيق الحزمة) لكل المنصات المستهدفة، ثم شغّل أمر التوليد.
- لا تستخدم `flutter_launcher_icons`.

---

## 10. المنصات والمعماريات (إلزامي)

الأهداف: كل المنصات المطابقة لـ `TARGETS` (الافتراضي كلها): Windows، Linux، macOS، Android، Flatpak (منفصل عن حزم Linux الأصلية)، iOS، Web. لا تتخطَّ أيًّا من المنصات المطلوبة.

المعماريات المطلوبة: x86-64، AArch64 (ARM64)، ARMv7 (32-bit)، x86-32 (32-bit)، **حيثما تدعمها المنصة فعليًا**. Flutter الرسمي يدعم:

| المنصة | المعماريات المدعومة |
|---|---|
| Android | x64، Arm64، Arm32 (ARMv7) |
| iOS | Arm64 |
| macOS | x64، Arm64 (يفضَّل universal) |
| Windows | x64، Arm64 |
| Linux | x64، Arm64 |
| Web | JavaScript / WebAssembly |

- ARMv7 على غير أندرويد، وx86-32 في أي منصة، **غير مدعومة من Flutter**: لا تحاول بناءها ولا تلفّق لها مخرجات. سجّلها في `BUILD_NOTES.md` كغير مدعومة.
- لو معمارية مدعومة لكن لا يمكن بناؤها من جهاز البناء الحالي (مثل iOS/macOS خارج macOS، أو Arm64 بدون cross-build): السكربت يطبع رسالة واضحة ويبني ما يمكن، والأمر الكامل يُدوَّن في `BUILD_NOTES.md`.
- `BUILD_NOTES.md` يحتوي أمر بناء كل منصة ومتطلبات جهاز البناء.
- **الميزات غير الممكنة على منصة** (مثل FFmpeg على الويب وiOS، أو الوصول للملفات، أو ميزة خاصة بنظام): لا تلفّقها ولا تنفّذ نسخة مزيفة. عطّلها بوضوح في واجهة تلك المنصة برسالة مترجمة، واستخدم بديلًا حقيقيًا إن وُجد، ووثّق ذلك في `PROJECT_NOTES.md`.

---

## 11. `build_linux.sh`

(فقط إذا كان Linux ضمن المنصات المطلوبة.)

ينتج **كل** التالي داخل مجلد `/dist`:

- `.rpm` (متوافق مع dnf/yum/zypper، مع dependencies صحيحة)
- `.deb`
- `.pkg.tar.zst` (Arch/pacman)
- `.tar.gz` (أرشيف عام)
- `AppImage`

المتطلبات: الإصدار يؤخذ من `pubspec.yaml`، ملف `.desktop` والأيقونة داخل كل حزمة، والسكربت يتحقق من وجود الأدوات المطلوبة ويفشل برسالة واضحة إن غابت (`fpm` مقبول). كل معمارية Linux مدعومة (x64، Arm64) لها مخرجاتها.

---

## 12. `flatpak_linux.sh`

(فقط إذا كان Flatpak ضمن المنصات المطلوبة.)

يقرأ من مجلد `flatpak/` الذي يحتوي:

- `{{APP_ID}}.json` (manifest)
- `{{APP_ID}}.metainfo.xml`
- `{{APP_ID}}.desktop`

`{{APP_ID}}` هو الـ reverse-DNS الخاص بالمشروع، وليس بادئة ثابتة. المخرجات أيضًا في `/dist`. اختر runtime يناسب bundle الخاص بـ Flutter على Linux.

---

## 13. ملفات التوثيق للـ agent

أنشئ `PROJECT_NOTES.md` (وملف `AGENTS.md` من سطر واحد يشير إليه) ويحتويان:

- وصف التطبيق، والهيكل، والقرارات والافتراضات التي اتخذتها، وجدول «ميزة × منصة» يوضح ما يعمل وما يُعطَّل على كل منصة ولماذا.
- **قاعدة إلزامية:** أي تعديل أو ميزة جديدة يجب أن تُطبَّق على المجلدات الثلاثة `screens/mobile` و`screens/desktop` و`screens/web` (أو على المجلدات الموجودة فقط حسب `TARGETS`). لا تنهِ أي جلسة قبل التأكد من ذلك.
- لا ألوان ثابتة ولا نصوص ثابتة داخل الـ widgets.

---

## 14. المهارات التي يجب أن يتعلمها الـ agent قبل البدء

قبل كتابة أي كود: اقرأ توثيق كل بند أدناه فعليًا (pub.dev، توثيق الحزمة، man pages، توثيق المنصة)، ثم أنشئ في `PROJECT_NOTES.md` قسم «Skills learned» بسطر لكل بند (ما تعلمته وأين سيُطبَّق). لا تعتمد على الذاكرة في الإصدارات والـ APIs: تحقق من أحدث إصدار ثابت لكل حزمة على pub.dev قبل إضافتها إلى `pubspec.yaml`.

- Flutter gen-l10n وملفات ARB ودعم RTL
- تخطيطات متجاوبة بـ `LayoutBuilder` وتخصيص التصميم لكل منصة
- `window_manager` وإدارة نافذة سطح المكتب
- `shared_preferences` و`url_launcher`
- `icons_launcher` 3.1.0
- تغليف Linux: rpm، deb، pkg.tar.zst، tar.gz، AppImage، Flatpak
- تضمين Chromium عبر CEF في Flutter Desktop (`webview_cef` أو ما يعادله): Texture rendering، browser instances متعددة، command-line switches، request handlers، حقن CSS/JS، `WasHidden`
- اعتراض الطلبات وحجبها على مستوى المحرك (حاجب إعلانات)، وCSS cosmetic filtering، وسكربتات YouTube الدفاعية
- التحكم بالموارد عبر النظام: Windows Job Objects وaffinity، Linux `sched_setaffinity` وcgroup v2 و`systemd-run`، واختيار GPU (`DRI_PRIME`، NVIDIA PRIME offload، تفضيل GPU في Windows)، مع `dart:ffi`
- إدارة التبويبات: نوم/إيقاظ instances، استعادة الجلسة بعد الانهيار، التحميل المسبق (preconnect/prefetch/prerender)
- SQLite في Flutter Desktop (`sqflite_common_ffi` أو `drift`)
- كودكات الفيديو في Chromium/CEF وحدود الـ proprietary codecs، وsandbox على Linux داخل AppImage وFlatpak (zypak / user namespaces)
- `dart:ffi` وplatform channels وTexture في Flutter Desktop، وكتابة كود أصلي (C++/Obj-C++) وربطه بـ CMake/CocoaPods
- أدوات بناء سطح المكتب لكل نظام: MSVC/CMake على Windows، clang/ninja/GTK على Linux، Xcode/CocoaPods على macOS
- Dart isolates للأعمال الخلفية (حفظ الجلسة، قاعدة البيانات) بدون تجميد الواجهة
- اختصارات لوحة المفاتيح في Flutter Desktop (`Shortcuts`/`Actions`/`CallbackShortcuts`) وسحب العناصر لإعادة الترتيب (`ReorderableListView` أو ما يعادله)
- التحقق من إصدارات الحزم على pub.dev وقراءة changelog وقيود الـ SDK قبل الاعتماد عليها

---

## 15. معيار الإنجاز

- `flutter analyze` بدون أخطاء، والتطبيق يعمل بدون overflow على الأحجام المختلفة.
- لا نصوص ولا ألوان ثابتة داخل الـ widgets.
- كل المنصات المطلوبة مغطاة (وغير المدعومة موثقة في `BUILD_NOTES.md`).
- كل الملفات مكتوبة بالكامل بدون `TODO` أو اختصارات.
- نُفِّذت حلقة التحقق النهائي (بند 8 في عقد التنفيذ الصارم) وكل بند في هذا الملف له ملف يطبّقه في التقرير الأخير.
