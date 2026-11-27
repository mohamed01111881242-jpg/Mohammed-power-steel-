# إعداد منصة المعارف وربط Supabase

## المشروع المتصل
- اسم مشروع Supabase: `al-maaref-platform`
- Project Ref: `llkxjglbxxsrhagjfhqx`
- حالة المشروع وقت آخر فحص: ACTIVE_HEALTHY
- الواجهة: `index.html`
- مخطط قاعدة البيانات الأساسي: `supabase/schema.sql` (مرجع لإنشاء مشروع جديد فقط، لا تعِد تشغيله على المشروع الحالي).

## الترحيلات الموجودة
1. `supabase/migrations/20261127_directory_and_profiles.sql`
2. `supabase/migrations/20261127173046_subscription_policy_and_private_rls_helpers.sql`
3. `supabase/migrations/20261127190000_cloud_marketplace_onboarding_and_matching.sql`

## ما يعمل في الواجهة
- اتصال Supabase باستخدام Project URL وpublishable key.
- تسجيل الدخول عبر OTP للهاتف.
- إنشاء نشاط وعضوية مالك في معاملة واحدة بواسطة `create_organization_with_owner`.
- دليل الأنشطة العامة.
- نشر الطلبات والعروض في قاعدة البيانات المشتركة.
- تحديث القوائم بعد تسجيل الدخول وإضافة البيانات.

## ما يجب إعداده يدويًا
1. في Supabase: Authentication → Providers → Phone، فعّل تسجيل الهاتف.
2. اربط مزود SMS وأكمل إعداد القوالب والحدود.
3. اختبر إرسال الرمز والتحقق منه على هاتف فعلي.
4. سجّل دخول المؤسس، ثم أضف معرّف المستخدم الموثق إلى `public.platform_admins` من SQL Editor بواسطة مسؤول المشروع فقط.
5. اختبر حسابين مختلفين للتأكد من أن كل حساب يرى بياناته الخاصة وما هو معلن للعامة فقط.

## الأمان
- لا تشارك `service_role` أو مفاتيح سرية في الواجهة أو GitHub.
- لا تضع WhatsApp access token أو مفاتيح الذكاء الاصطناعي في المتصفح.
- لا تقبل دفعة أو تفعّل اشتراكًا بناءً على نتيجة يرسلها المتصفح؛ يجب التحقق من Webhook في الخادم.
- لا تعتمد عرض سعر أو اتفاقًا ماليًا دون موافقة بشرية.

## ما لم يكتمل
- WhatsApp Business Cloud API وWebhook.
- مساعد ذكاء اصطناعي بمفتاح محفوظ في أسرار الخادم.
- بوابة دفع إلكتروني مصرية.
- تذكيرات الاشتراك وتطبيق حدود الخطط.
- اختبار OTP وRLS على حسابات حقيقية قبل الإطلاق.
