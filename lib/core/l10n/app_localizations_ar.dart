// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appName => 'سرب';

  @override
  String get intro => 'مساحة أخف للويب والفيديو. تبويباتك ومواردك تحت سيطرتك.';

  @override
  String get next => 'متابعة';

  @override
  String get language => 'اللغة';

  @override
  String get english => 'English';

  @override
  String get arabic => 'العربية';

  @override
  String get theme => 'المظهر';

  @override
  String get dark => 'داكن';

  @override
  String get light => 'نهاري';

  @override
  String get system => 'حسب النظام';

  @override
  String get start => 'ابدأ التصفح';

  @override
  String get fullscreen => 'ملء الشاشة';

  @override
  String get settings => 'الإعدادات';

  @override
  String get general => 'عام';

  @override
  String get performance => 'الأداء';

  @override
  String get ads => 'حاجب الإعلانات';

  @override
  String get privacy => 'الخصوصية والبيانات';

  @override
  String get developer => 'المطور';

  @override
  String get email => 'البريد الإلكتروني';

  @override
  String get website => 'الموقع';

  @override
  String get launchFailed => 'تعذر فتح الرابط.';

  @override
  String get newTab => 'تبويب جديد';

  @override
  String get searchHint => 'ابحث في DuckDuckGo أو أدخل عنوانًا';

  @override
  String get addressHint => 'ابحث أو أدخل عنوانًا';

  @override
  String get search => 'بحث';

  @override
  String get mostVisited => 'الأكثر زيارة';

  @override
  String get back => 'رجوع';

  @override
  String get forward => 'تقدم';

  @override
  String get reload => 'إعادة تحميل';

  @override
  String get stop => 'إيقاف';

  @override
  String get home => 'الرئيسية';

  @override
  String get find => 'بحث في الصفحة';

  @override
  String get findNext => 'النتيجة التالية';

  @override
  String get findPrevious => 'النتيجة السابقة';

  @override
  String get close => 'إغلاق';

  @override
  String get zoomIn => 'تكبير';

  @override
  String get zoomOut => 'تصغير';

  @override
  String get zoomReset => 'إعادة ضبط التكبير';

  @override
  String get downloads => 'التنزيلات';

  @override
  String get openBatch => 'فتح روابط متعددة';

  @override
  String get openBatchHint => 'أدخل الروابط (رابط في كل سطر):';

  @override
  String get openTabs => 'فتح التبويبات';

  @override
  String get empty => 'لا توجد عناصر بعد';

  @override
  String get history => 'سجل الصفحات';

  @override
  String get tabHistory => 'سجل التبويبات المغلقة';

  @override
  String get restore => 'استرجاع';

  @override
  String get restoreSession => 'هل تريد استرجاع الجلسة السابقة؟';

  @override
  String get yes => 'استرجاع';

  @override
  String get no => 'صفحة جديدة';

  @override
  String get startup => 'عند بدء التشغيل';

  @override
  String get startupNew => 'صفحة جديدة';

  @override
  String get startupRestore => 'استعادة آخر جلسة';

  @override
  String get startupAsk => 'اسأل في كل مرة';

  @override
  String get searchEngine => 'محرك البحث';

  @override
  String get duckduckgo => 'DuckDuckGo';

  @override
  String get searchTabs => 'بحث في التبويبات';

  @override
  String get collapse => 'طي التبويبات';

  @override
  String get expand => 'توسيع التبويبات';

  @override
  String get pin => 'تثبيت / إلغاء التثبيت';

  @override
  String get mute => 'كتم / إلغاء الكتم';

  @override
  String get duplicate => 'تكرار';

  @override
  String get closeOthers => 'إغلاق التبويبات الأخرى';

  @override
  String get closeAfter => 'إغلاق ما بعده';

  @override
  String get closeAll => 'إغلاق الكل';

  @override
  String get sleep => 'إنامة التبويب';

  @override
  String get sleeping => 'نائم';

  @override
  String get live => 'نشط';

  @override
  String get background => 'خلفي';

  @override
  String get playing => 'يشغّل وسائط — محمي من النوم';

  @override
  String tabCount(int count) {
    return '$count تبويبًا';
  }

  @override
  String operation(int count, String time) {
    return '$count تبويبًا مغلقًا · $time';
  }

  @override
  String get delete => 'حذف';

  @override
  String get deleteAll => 'حذف الكل';

  @override
  String get deleteRange => 'حذف نطاق زمني';

  @override
  String get lastHour => 'آخر ساعة';

  @override
  String get lastDay => 'آخر يوم';

  @override
  String get lastWeek => 'آخر أسبوع';

  @override
  String get clearHistory => 'مسح سجل الصفحات';

  @override
  String get clearCookies => 'مسح الكوكيز';

  @override
  String get clearCache => 'مسح الكاش وإعادة التشغيل';

  @override
  String get dataCleared => 'تم مسح البيانات';

  @override
  String get confirmDelete =>
      'سيُحذف المحتوى المحدد نهائيًا. هل تريد المتابعة؟';

  @override
  String get cancel => 'إلغاء';

  @override
  String get cpu => 'أقصى عدد أنوية CPU';

  @override
  String get ram => 'أقصى RAM';

  @override
  String get gpu => 'كرت الشاشة';

  @override
  String get automatic => 'تلقائي';

  @override
  String get discrete => 'منفصل';

  @override
  String get integrated => 'مدمج';

  @override
  String get acceleration => 'تسريع الأجهزة';

  @override
  String get unlimited => 'بدون حد';

  @override
  String get idleMinutes => 'مهلة نوم التبويبات الخاملة';

  @override
  String get disabled => 'معطل';

  @override
  String minutes(int count) {
    return '$count دقيقة';
  }

  @override
  String get liveLimit => 'أقصى عدد تبويبات حية';

  @override
  String get preload => 'تحميل روابط الفيديو مسبقًا عند المرور';

  @override
  String get preloadLimit => 'التحميلات المسبقة المتزامنة';

  @override
  String get restart => 'طبّق وأعد التشغيل';

  @override
  String get restartRequired =>
      'تغييرات CPU وRAM وGPU تُطبّق بعد إعادة التشغيل. ستُستعاد جلستك.';

  @override
  String get cpuUnavailable => 'لا يدعم نظام التشغيل تحديد أنوية CPU.';

  @override
  String get gpuUnavailable =>
      'يدير النظام اختيار الكرت، أو لم يُكتشف زوج كروت مناسب.';

  @override
  String get hardRamUnavailable =>
      'الحد الصارم للذاكرة غير متاح هنا. يبقى النوم ضمن حد ناعم فعالًا.';

  @override
  String get hardRam => 'حد RAM صارم عبر النظام';

  @override
  String get device => 'الجهاز المكتشف';

  @override
  String cores(int count) {
    return '$count نواة منطقية';
  }

  @override
  String gigabytes(String value) {
    return '$value GB';
  }

  @override
  String usage(String value) {
    return 'ذاكرة التطبيق وعملياته: $value';
  }

  @override
  String get unknownHardware => 'معلومات الجهاز غير متاحة';

  @override
  String resourceError(String error) {
    return 'تعذر تطبيق الموارد: $error';
  }

  @override
  String get resourcePressure =>
      'الذاكرة قريبة من الحد. لن تُقطع التبويبات التي تشغّل وسائط.';

  @override
  String get blockEnabled => 'تفعيل حاجب الإعلانات';

  @override
  String get siteBlocking => 'تبديل الحجب على هذا الموقع';

  @override
  String blocked(int count) {
    return 'حُجب $count طلبًا';
  }

  @override
  String get allowlist => 'المواقع المستثناة من الحجب';

  @override
  String get remove => 'إزالة';

  @override
  String get adNotice =>
      'يتغير YouTube باستمرار. قد تحتاج القواعد إلى تحديث؛ لا يمكن ضمان إزالة الإعلانات المدمجة في البث.';

  @override
  String get codecNotice =>
      'تتوفر كودكات VP9/AV1/Opus. لا يتوفر بث HLS بكودكات H.264/AAC في نسخة CEF الرسمية المضمّنة؛ يلزم بناء CEF مخصص مرخّص قانونيًا ومشغّل يدعم HLS.';

  @override
  String engineError(String error) {
    return 'تعذر بدء Chromium: $error';
  }

  @override
  String pageError(String error) {
    return 'تعذر تحميل الصفحة: $error';
  }

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get downloadComplete => 'مكتمل';

  @override
  String get downloadCanceled => 'ملغى';

  @override
  String downloadProgress(int value) {
    return '$value%';
  }

  @override
  String get openFile => 'فتح الملف المنزّل';

  @override
  String get devtools => 'أدوات المطور';

  @override
  String get save => 'حفظ';

  @override
  String get loading => 'جارٍ التحميل';

  @override
  String get confirm => 'تأكيد';

  @override
  String get profile => 'ملف المتصفح الدائم';

  @override
  String get mediaTests => 'تشخيص الصوت والرسوم';

  @override
  String get runMediaTests => 'فحص الكودكات والصوت والرسوم';

  @override
  String testResult(String value) {
    return 'التشخيص: $value';
  }

  @override
  String get openLinkInNewTab => 'فتح الرابط في علامة تبويب جديدة';

  @override
  String get copyLinkAddress => 'نسخ عنوان الرابط';

  @override
  String get copy => 'نسخ';

  @override
  String get paste => 'لصق';

  @override
  String get cut => 'قص';

  @override
  String get selectAll => 'تحديد الكل';

  @override
  String get errorLogs => 'سجلات الأخطاء';

  @override
  String get adErrorLogs => 'سجلات أخطاء الإعلانات';

  @override
  String get copyAll => 'نسخ الكل';

  @override
  String get copiedToClipboard => 'تم النسخ إلى الحافظة';

  @override
  String get clearLogs => 'حذف السجلات';

  @override
  String get confirmDeleteLogs =>
      'هل أنت متأكد من حذف جميع سجلات الأخطاء؟ لا يمكن التراجع عن هذا الإجراء.';

  @override
  String get exportTxt => 'تصدير TXT';

  @override
  String logsExported(String path) {
    return 'تم تصدير السجلات إلى $path';
  }

  @override
  String get allLogs => 'الكل';

  @override
  String get adLogs => 'أخطاء الإعلانات';

  @override
  String get networkLogs => 'الشبكة';

  @override
  String get crashLogs => 'الأعطال';

  @override
  String get systemLogs => 'النظام';

  @override
  String logUrl(String url) {
    return 'رابط الموقع: $url';
  }

  @override
  String errorDetails(String details) {
    return 'التفاصيل: $details';
  }

  @override
  String totalLogs(int count) {
    return '$count سجل';
  }

  @override
  String get openGameWindow => 'فتح في نافذة ألعاب أصلية';

  @override
  String get gameWindowNotice =>
      'ستُعاد الصفحة في نافذة Chromium مستقلة تابعة لسرب تدعم التقاط الماوس الحقيقي. تبقى طلبات الإذن العادية مفعّلة؛ اضغط Esc لتحرير الماوس. يُفرّغ التبويب الحالي بعد فتح النافذة فقط لتجنب تحميل اللعبة مرتين. تتوفر نافذة ألعاب واحدة؛ تُغلق مع سرب ولا تُستعاد بعد إعادة التشغيل.';

  @override
  String get javascriptLogs => 'JavaScript / وحدة التحكم';

  @override
  String get graphicsLogs => 'الرسوم';

  @override
  String get mediaLogs => 'الصوت / الفيديو';

  @override
  String get permissionLogs => 'الأذونات / الماوس';

  @override
  String get flutterLogs => 'Flutter';

  @override
  String get loadMoreLogs => 'تحميل السجلات الأقدم';

  @override
  String get errorCaptureNotice =>
      'يسجّل تحذيرات وأخطاء وحدة التحكم، وأخطاء JavaScript والوعود غير المعالجة، وفشل الموارد، وفشل واجهات الماوس والصوت والرسوم التي تتم مراقبتها. قد لا تظهر الأخطاء التي يخفيها الموقع داخليًا أو بعض العمال؛ خلو السجل لا يعني عدم وجود أخطاء. قد تتضمن السجلات روابط أو رسائل خاصة.';

  @override
  String get preferredGpu => 'المفضّل';

  @override
  String get gameMode => 'وضع الألعاب';

  @override
  String get gameModeNotice =>
      'إيقاف التحميل الاستباقي للفيديو. عند اختيار الرسوم التلقائية وتفعيل تسريع العتاد، يُفضّل الكرت المنفصل بعد إعادة التشغيل على الأجهزة المدعومة ذات الكرتين. يبقى اختيارك الصريح للكرت وحدود CPU وRAM وحماية تبويبات الوسائط كما هي. هذا ليس تبديلًا أثناء اللعب أو ضمانًا لعدد الإطارات.';

  @override
  String get graphicsCompatibility => 'توافق الرسوم (WebGL)';

  @override
  String get graphicsCompatibilityNotice =>
      'تعطيل WebGPU للسماح للألعاب المتوافقة بالرجوع إلى WebGL المسرّع. جرّبه عند ظهور خطأ فقدان جهاز WebGPU. يتطلب إعادة التشغيل؛ المواقع التي تعتمد على WebGPU فقط لن تعمل.';

  @override
  String get gpuSchedulingNotice =>
      'يختار النظام والتعريف كرت العرض. لا يستطيع المتصفح دمج ذاكرة الكرت المدمج والمنفصل أو فرض استخدام 100٪. قد يدل الاستخدام المنخفض على اختناق CPU أو حد الإطارات أو كلفة نسخها.';

  @override
  String get mouseNavigation => 'أزرار الماوس الجانبية';

  @override
  String get mouseNavigationSubtitle =>
      'التنقل للرجوع والتقدم باستخدام أزرار الماوس الجانبية';
}
