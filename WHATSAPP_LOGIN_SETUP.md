# تفعيل تسجيل الدخول عبر واتساب — منصة المعارف

## الحالة الحالية
- واجهتا العميل ومقدم الخدمة تطلبان رمز الدخول عبر قناة WhatsApp من Supabase Auth.
- التحقق من الرمز يتم عبر `verifyOtp({ phone, token, type: 'sms' })`. هذه هي قيمة `type` التي توثقها Supabase لرموز الهاتف حتى عند اختيار قناة WhatsApp.
- واجهة الإدارة ما زالت تستخدم البريد الإلكتروني وكلمة المرور.
- استقبال رسائل العملاء والردود عبر WhatsApp Business Cloud API في دالة `whatsapp-webhook` مسار منفصل عن OTP.

## المتطلب الخارجي الذي لم يكتمل
Supabase يدعم قناة WhatsApp لتسجيل الدخول عبر Twilio أو Twilio Verify فقط. وجود WhatsApp Business Cloud API وحده لا يفعّل OTP داخل Supabase.

## خطوات الإعداد المطلوبة من مالك الحساب
1. إنشاء حساب Twilio وتفعيل WhatsApp sender / WhatsApp channel حسب متطلبات Twilio.
2. إنشاء Verify Service في Twilio، والتأكد من تفعيل قناة WhatsApp للخدمة.
3. فتح [إعدادات مزودي الدخول في مشروع Supabase](https://supabase.com/dashboard/project/llkxjglbxxsrhagjfhqx/auth/providers).
4. تفعيل Phone provider واختيار Twilio Verify، ثم إدخال Verify Service SID وحفظ الإعداد.
5. التأكد من أن رقم WhatsApp المرسل معتمد ومسموح له بإرسال رسائل التحقق للمستخدمين في مصر.
6. اختبار رقم مصري بصيغة دولية +20 من صفحة العميل، ثم تجربة صفحة مقدم الخدمة بحساب منفصل.

## ملاحظات أمان وتشغيل
- لا ترسل Account SID أو Auth Token أو مفاتيح Twilio في المحادثة. أدخلها فقط داخل لوحة Twilio / Supabase الرسمية.
- لا نستخدم SMS كقناة احتياطية؛ إذا فشل WhatsApp تظهر رسالة خطأ للمستخدم.
- لا نعتبر تسجيل الدخول مكتملاً حتى تصل رسالة OTP فعلية ويُقبل الرمز وتُنشأ جلسة Supabase.
- قد تترتب رسوم على رسائل WhatsApp / Twilio واشتراك Twilio حسب الخطة والاستخدام؛ راجع الأسعار قبل تفعيل الإرسال على نطاق واسع.
