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
4. `supabase/migrations/20261127191500_authenticated_business_directory.sql`
5. `supabase/migrations/20261127193000_private_auth_profile_bootstrap.sql`
6. `supabase/migrations/20261127194500_offer_decision_workflow.sql`
7. `supabase/migrations/20261127200000_whatsapp_inbox_foundation.sql`
8. `supabase/migrations/20261127201500_whatsapp_conversation_history.sql`

## ما يعمل في الواجهة
- اتصال Supabase باستخدام Project URL وpublishable key.
- تسجيل الدخول عبر OTP للهاتف.
- إنشاء نشاط وعضوية مالك في معاملة واحدة بواسطة `create_organization_with_owner`.
- دليل الأنشطة العامة.
- نشر الطلبات والعروض في قاعدة البيانات المشتركة.
- مطابقة الطلبات حسب التخصص والمنطقة.
- قبول/رفض العروض من صاحب الطلب، وتحويل الطلب إلى قيد التنفيذ عند القبول.
- تحديث القوائم بعد تسجيل الدخول وإضافة البيانات.

## WhatsApp Webhook المنشور
- الوظيفة: `whatsapp-webhook` (منشورة، وتتحقق من توقيع Meta).
- الرابط: `https://llkxjglbxxsrhagjfhqx.supabase.co/functions/v1/whatsapp-webhook`
- المصدر: `supabase/functions/whatsapp-webhook/index.ts`.
- تحفظ الرسائل الواردة وسجل الردود في `public.whatsapp_inbox`، وتمنع تكرار الرد على نفس معرّف الرسالة.
- يمكنها إنشاء رد عربي عبر OpenAI وإرساله من WhatsApp بعد ضبط جميع الأسرار. لا تُرسل ردودًا تلقائية قبل إعدادها.

## ما يجب إعداده يدويًا
1. في Supabase: Authentication → Providers → Phone، فعّل تسجيل الهاتف.
2. اربط مزود SMS وأكمل إعداد القوالب والحدود.
3. اختبر إرسال الرمز والتحقق منه على هاتف فعلي.
4. سجّل دخول المؤسس، ثم أضف معرّف المستخدم الموثق إلى `public.platform_admins` من SQL Editor بواسطة مسؤول المشروع فقط.
5. اختبر حسابين مختلفين للتأكد من أن كل حساب يرى بياناته الخاصة وما هو معلن للعامة فقط.
6. من Supabase → Edge Functions → Secrets أضف: `WHATSAPP_VERIFY_TOKEN` (قيمة تختارها أنت وتضعها نفسها في إعداد Meta)، و`WHATSAPP_APP_SECRET`، و`WHATSAPP_ACCESS_TOKEN`، و`WHATSAPP_PHONE_NUMBER_ID`، و`OPENAI_API_KEY`. اترك `SUPABASE_SERVICE_ROLE_KEY` ضمن أسرار Supabase الافتراضية ولا تنشره. يمكن ضبط `OPENAI_MODEL` اختياريًا؛ الافتراضي `gpt-6.2-astra`، ويمكن ضبط `WHATSAPP_GRAPH_VERSION` اختياريًا؛ الافتراضي `v27.0`.
7. في لوحة Meta أضف رابط Webhook أعلاه ورمز التحقق نفسه، ثم اشترك في حقل `messages`.
8. اختبر برسالة من رقم آخر. لا يبدأ الرد التلقائي قبل إضافة أسرار OpenAI وWhatsApp الصحيحة.

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
