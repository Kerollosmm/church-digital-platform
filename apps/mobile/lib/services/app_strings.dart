class AppStrings {
  AppStrings._();

  static const networkError = 'تعذّر الاتصال بالإنترنت';
  static const authInvalid = 'بيانات الدخول غير صحيحة';
  static const authExpired = 'جلسة منتهية، سجّل الدخول مجدداً';
  static const forbiddenError = 'لا تملك صلاحية للقيام بهذا الإجراء';
  static const notFoundError = 'لم يتم العثور على البيانات';
  static const conflictError = 'الموعد ممتلئ أو محجوز بالفعل';
  static const serverError = 'الخدمة غير متاحة حالياً';
  static const unknownError = 'حدث خطأ غير متوقع';

  static const slotUnavailable = 'الموعد غير متاح حالياً';
  static const slotFull = 'الموعد ممتلئ، اختر موعداً آخر';
  static const alreadyBooked = 'لديك حجز مسبق في هذا الموعد';
  static const tooManyActive = 'لديك عدد كبير من الحجوزات النشطة';
  static const bookingFailed = 'فشل الحجز، حاول مجدداً';

  static const otpSendFailed = 'تعذر إرسال الرمز';
  static const otpInvalid = 'الرمز غير صحيح';
  static const otpVerifyFailed = 'حدث خطأ أثناء التحقق';
  static const paymentOpenFailed = 'تعذر فتح صفحة الدفع';

  static const appTitle = 'الكنيسة القبطية الأرثوذكسية';
  static const announcementsTitle = 'إعلانات هامة';
  static const viewAll = 'عرض الكل';
  static const noAnnouncements = 'لا توجد إعلانات';
  static const quickServicesTitle = 'الخدمات السريعة';
  static const quickMass = 'مواعيد القداسات';
  static const quickConfession = 'الآباء والاعترافات';
  static const quickBooking = 'حجز المناسبات';
  static const quickComplaints = 'صندوق الشكاوى';
  static const meditationToday = 'تأمل اليوم';
  static const verseText = '"الرَّبُّ نُورِي وَخَلاَصِي، مِمَّنْ أَخَافُ؟"';
  static const verseRef = '(مزمور 27: 1)';
  static const tabHome = 'الرئيسية';
  static const tabBooking = 'الحجز';
  static const tabComplaints = 'الشكاوى';
  static const tabProfile = 'حسابي';
  static const comingSoon = 'قريباً';

  static const authTitle = 'الكنيسة القبطية الأرثوذكسية';
  static const authSubtitle = 'أهلاً بك في منصة الكنيسة Digital Platform';
  static const phoneLabel = 'رقم الهاتف المحمول';
  static const phoneHint = '10 0000 0000';
  static const sendOtpCta = 'إرسال رمز التحقق';
  static const invalidPhone = 'رقم غير صحيح';
  static const otpIntro = 'أدخل الرمز المكون من 6 أرقام المرسل إلى';
  static const changeNumber = 'تعديل الرقم';
  static const confirmOtp = 'تأكيد الدخول';
  static const resendPrompt = 'لم تستلم الرمز؟';
  static const resendOtp = 'إعادة إرسال';
  static const privacyPolicy = 'سياسة الخصوصية';
  static const termsConditions = 'الشروط والأحكام';
  static const support = 'الدعم الفني';

  static const completeBookingPrompt = 'يرجى إتمام الحجز خلال ٢٠:٠٠ دقيقة';
  static const selectSlot = 'اختر الموعد';
  static const statusAvailable = 'متاح';
  static const statusBooked = 'مكتمل';
  static const statusClosed = 'مغلق';
  static const arriveEarlyNotice = 'يرجى الحضور قبل الموعد بـ ١٥ دقيقة';
  static const whatsappOptIn = 'موافقة على استقبال رسائل واتساب';
  static const confirmBooking = 'تأكيد الحجز';
  static const cancel = 'إلغاء';
  static const bookingSummary = 'ملخص الحجز';
  static const egp = 'جنيه';
  static const priceFrom = 'تبدأ من';
  static const availableSeatsLabel = 'مقاعد متاحة';
  static const noAvailableSeats = 'لا يوجد مقاعد';
  static const notAvailablePublic = 'غير متاح للحجز العام';
  static const serviceDetails = 'تفاصيل الخدمة';

  static const myBookingsTitle = 'حجوزاتي';
  static const myBookingsEmpty = 'لا توجد حجوزات';
  static const bookingNumberPrefix = 'حجز #';
  static const retryPayment = 'إعادة الدفع';
  static const bookingConfirmedSuccess = 'تم تأكيد الحجز بنجاح';
  static const bookingNumberLabel = 'رقم الحجز:';
  static const showQrNotice = 'يرجى إبراز هذا الرمز عند الدخول';
  static const editBooking = 'تعديل';
  static const cancelBooking = 'إلغاء';
  static const backToHome = 'العودة للرئيسية';
  static const paidAmountLabel = 'المبلغ المدفوع';
  static const createdAtLabel = 'تاريخ الحجز';

  static const checkoutTitle = 'إتمام الدفع';
  static const checkoutSubtitle =
      'اختر وسيلة الدفع المناسبة لإتمام حجزك بأمان.';
  static const paymentMethodsTitle = 'طرق الدفع';
  static const cardMethod = 'البطاقات البنكية / ميزة';
  static const cardMethodDesc =
      'دفع آمن وسريع عبر بطاقات الخصم المباشر أو الائتمان.';
  static const fawryMethod = 'فوري باي (Fawry Pay)';
  static const fawryMethodDesc = 'احصل على كود وادفع من أي منفذ فوري.';
  static const walletMethod = 'المحافظ الإلكترونية';
  static const walletMethodDesc = 'فودافون كاش، اتصالات كاش، أورانج كاش.';
  static const securePaymentTitle = 'دفع آمن';
  static const securePaymentDesc =
      'عملية الدفع مشفرة ومؤمنة بالكامل عبر بوابة Paymob.';
  static const orderSummaryTitle = 'ملخص الطلب';
  static const payNow = 'ادفع الآن';
  static const termsNote =
      'بالنقر على "ادفع الآن"، أنت توافق على الشروط والأحكام.';
}
