# إعداد منصة المعارف وربط Supabase

## الحالة الحالية
- الواجهة العربية: موجودة في `index.html`.
- مخطط PostgreSQL الأساسي: `supabase/schema.sql`.
- تحسين دليل الأنشطة وإنشاء ملف المستخدم تلقائيًا: `supabase/migrations/20261127_directory_and_profiles.sql`.
- الواجهة الحالية تحفظ بيانات التجربة في المتصفح فقط. لم يتم توصيلها بقاعدة البيانات السحابية أو WhatsApp API بعد.

## خطوات إعداد قاعدة البيانات
1. افتح مشروع Supabase الصحيح.
2. افتح SQL Editor.
3. إذا لم تكن الجداول الأساسية موجودة، شغّل محتوى `supabase/schema.sql` أولًا.
4. شغّل محتوى ملف الترحيل `supabase/migrations/20261127_directory_and_profiles.sql`.
5. افتح Table Editor وتأكد من وجود: profiles, organizations, memberships, service_requests, offers, activity_log.
6. تأكد أن RLS مفعّل على الجداول قبل إدخال بيانات حقيقية.

## بيانات الربط المطلوبة للخطوة التالية
من Project Settings ثم API انسخ:
- Project URL
- publishable key أو anon public key

هذه مفاتيح عمومية مخصصة للواجهة، لكن لا ترسل أبدًا service_role key أو مفاتيح سرية أو WhatsApp access token. لا نضع أسرار الخادم في ملفات المتصفح أو GitHub.

## قبل تفعيل حسابات حقيقية
- مراجعة سياسات RLS واختبارها بحسابين مختلفين.
- إضافة مصادقة الهاتف/OTP وتدفق إنشاء النشاط والعضوية.
- توصيل نماذج التسجيل والطلبات والعروض بقاعدة البيانات.
- بناء وظائف خادم موثوقة لرسائل WhatsApp Cloud API؛ لا تُرسل رسائل آلية قبل إعداد Meta والتحقق من الرقم والقوالب المطلوبة.
- تفعيل مراجعة بشرية قبل اعتماد عروض الأسعار أو أي التزام مالي.

## نشر الواجهة
يمكن تفعيل GitHub Pages من إعدادات المستودع: Settings → Pages → Deploy from a branch → main → /(root)، إذا كانت الخاصية متاحة للمستودع.
