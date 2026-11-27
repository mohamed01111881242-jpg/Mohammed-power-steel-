import { createClient } from "npm:@supabase/supabase-js@2";

const headers = { "Content-Type": "application/json" };
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers });

function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function verifySignature(raw: string, supplied: string, secret: string) {
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(raw)));
  const hex = [...mac].map((b) => b.toString(16).padStart(2, "0")).join("");
  return safeEqual(supplied, `sha256=${hex}`);
}

function messageBody(m: any): string | null {
  if (m.type === "text") return m.text?.body ?? null;
  if (m.type === "button") return m.button?.text ?? null;
  if (m.type === "interactive") return m.interactive?.button_reply?.title ?? m.interactive?.list_reply?.title ?? null;
  if (["image", "video", "document"].includes(m.type)) return m[m.type]?.caption ?? `[رسالة ${m.type}]`;
  if (m.type === "location") return "[مشاركة موقع]";
  return m.type ? `[رسالة ${m.type}]` : null;
}

function outputText(data: any): string {
  for (const item of data.output ?? []) {
    if (item.type !== "message") continue;
    for (const part of item.content ?? []) {
      if (part.type === "output_text" && part.text) return String(part.text).trim();
    }
  }
  return "";
}

async function generateReply(supabase: any, phone: string): Promise<string> {
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) throw new Error("OPENAI_API_KEY is not configured");
  const { data: history, error } = await supabase
    .from("whatsapp_inbox")
    .select("direction,body")
    .eq("conversation_phone", phone)
    .not("body", "is", null)
    .order("received_at", { ascending: false })
    .limit(12);
  if (error) throw error;

  const input = (history ?? []).reverse().map((m: any) => ({
    role: m.direction === "outbound" ? "assistant" : "user",
    content: m.body,
  }));
  const instructions = `أنت المساعد الرسمي لمنصة المعارف، منصة مصرية تربط الشركات والمقاولين والورش والمصانع والمهنيين والموردين والعملاء.
تحدث بالعربية المصرية الواضحة وباختصار وبلطف. اسأل سؤالًا واحدًا في كل مرة لتفهم احتياج الشخص وتوجهه إلى التسجيل أو نشر طلب أو البحث عن مقدم خدمة.
لا تخترع أسعارًا أو توافرًا أو تقييمات أو بيانات شركات. لا تؤكد قبول عرض أو عقد أو دفع أو حجز أو التزام مالي. أي سعر نهائي أو اتفاق يحتاج موافقة بشرية من صاحب النشاط.
لا تطلب كلمات مرور أو أكواد OTP أو بيانات بطاقات أو حسابات بنكية أو أرقام هوية. لا تكشف بيانات خاصة عن أي مستخدم أو منشأة.
إذا طلب الشخص موظفًا بشريًا، أخبره أن فريق المنصة يحتاج متابعة طلبه ولا تدّعِ أن موظفًا تم إبلاغه ما لم يحدث ذلك.
إذا كانت الرسالة غير واضحة، اطلب توضيحًا واحدًا. إذا أرسل صورة أو ملفًا ولم تتوفر رؤيته هنا، اطلب وصفًا نصيًا.`;
  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: Deno.env.get("OPENAI_MODEL") ?? "gpt-6.2-astra",
      instructions,
      input,
      max_output_tokens: 260,
      store: false,
    }),
  });
  const data = await response.json();
  if (!response.ok) throw new Error(data.error?.message ?? "OpenAI response failed");
  const reply = outputText(data);
  if (!reply) throw new Error("The assistant returned no text");
  return reply.slice(0, 3500);
}

async function sendWhatsApp(to: string, body: string) {
  const token = Deno.env.get("WHATSAPP_ACCESS_TOKEN");
  const phoneNumberId = Deno.env.get("WHATSAPP_PHONE_NUMBER_ID");
  if (!token || !phoneNumberId) throw new Error("WhatsApp sending secrets are not configured");
  const version = Deno.env.get("WHATSAPP_GRAPH_VERSION") ?? "v27.0";
  const response = await fetch(`https://graph.facebook.com/${version}/${phoneNumberId}/messages`, {
    method: "POST",
    headers: { "Authorization": `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      messaging_product: "whatsapp",
      recipient_type: "individual",
      to: to.replace(/^\+/, ""),
      type: "text",
      text: { preview_url: false, body },
    }),
  });
  const data = await response.json();
  if (!response.ok) throw new Error(data.error?.message ?? "WhatsApp send failed");
  return data;
}

Deno.serve(async (req: Request) => {
  if (req.method === "GET") {
    const verifyToken = Deno.env.get("WHATSAPP_VERIFY_TOKEN");
    if (!verifyToken) return json({ error: "Set WHATSAPP_VERIFY_TOKEN in Edge Function secrets" }, 503);
    const url = new URL(req.url);
    const mode = url.searchParams.get("hub.mode") ?? "";
    const token = url.searchParams.get("hub.verify_token") ?? "";
    const challenge = url.searchParams.get("hub.challenge") ?? "";
    if (mode === "subscribe" && challenge && safeEqual(token, verifyToken)) {
      return new Response(challenge, { status: 200, headers: { "Content-Type": "text/plain" } });
    }
    return json({ error: "Webhook verification failed" }, 403);
  }
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const appSecret = Deno.env.get("WHATSAPP_APP_SECRET");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!appSecret || !supabaseUrl || !serviceRoleKey) {
    return json({ error: "Set WHATSAPP_APP_SECRET; Supabase server credentials are required" }, 503);
  }

  const raw = await req.text();
  const signature = req.headers.get("x-hub-signature-256") ?? "";
  if (!signature || !(await verifySignature(raw, signature, appSecret))) {
    return json({ error: "Invalid webhook signature" }, 401);
  }

  let payload: any;
  try { payload = JSON.parse(raw); } catch { return json({ error: "Invalid JSON" }, 400); }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let stored = 0, replied = 0;
  for (const entry of payload.entry ?? []) {
    for (const change of entry.changes ?? []) {
      const value = change.value ?? {};
      for (const message of value.messages ?? []) {
        const digits = String(message.from ?? "").replace(/\D/g, "");
        if (!digits || !message.id) continue;
        const customerPhone = `+${digits}`;
        const body = messageBody(message);
        const timestamp = Number(message.timestamp);
        const receivedAt = Number.isFinite(timestamp) && timestamp > 0
          ? new Date(timestamp * 1000).toISOString() : new Date().toISOString();

        let profileId: string | null = null;
        const profile = await supabase.from("profiles").select("id").eq("phone", customerPhone).maybeSingle();
        if (!profile.error) profileId = profile.data?.id ?? null;

        const { error: insertError } = await supabase.from("whatsapp_inbox").upsert({
          wa_message_id: message.id,
          profile_id: profileId,
          from_phone: customerPhone,
          to_phone: value.metadata?.display_phone_number ?? null,
          conversation_phone: customerPhone,
          direction: "inbound",
          message_type: message.type ?? "unknown",
          body,
          raw_payload: message,
          received_at: receivedAt,
          processing_status: "received",
        }, { onConflict: "wa_message_id", ignoreDuplicates: true });
        if (insertError) {
          console.error("Could not store WhatsApp message", insertError);
          continue;
        }
        stored++;

        // Claim once so Meta retries or duplicate webhook deliveries do not send duplicate AI replies.
        const { data: claimed, error: claimError } = await supabase
          .from("whatsapp_inbox")
          .update({ processing_status: "processing" })
          .eq("wa_message_id", message.id)
          .eq("processing_status", "received")
          .select("id")
          .maybeSingle();
        if (claimError || !claimed) continue;

        // Keep receiving messages even before the owner adds the AI and WhatsApp sending secrets.
        if (!Deno.env.get("OPENAI_API_KEY") || !Deno.env.get("WHATSAPP_ACCESS_TOKEN") || !Deno.env.get("WHATSAPP_PHONE_NUMBER_ID")) {
          await supabase.from("whatsapp_inbox").update({ processing_status: "received" }).eq("wa_message_id", message.id);
          continue;
        }

        try {
          const reply = await generateReply(supabase, customerPhone);
          const sent = await sendWhatsApp(customerPhone, reply);
          const businessPhone = value.metadata?.display_phone_number ?? null;
          const outboundId = sent.messages?.[0]?.id;
          if (outboundId) {
            await supabase.from("whatsapp_inbox").upsert({
              wa_message_id: outboundId,
              profile_id: profileId,
              from_phone: businessPhone ?? "business",
              to_phone: customerPhone,
              conversation_phone: customerPhone,
              direction: "outbound",
              message_type: "text",
              body: reply,
              raw_payload: sent,
              received_at: new Date().toISOString(),
              processed_at: new Date().toISOString(),
              processing_status: "processed",
            }, { onConflict: "wa_message_id", ignoreDuplicates: true });
          }
          await supabase.from("whatsapp_inbox").update({
            processing_status: "processed", processed_at: new Date().toISOString(),
          }).eq("wa_message_id", message.id);
          replied++;
        } catch (error) {
          console.error("WhatsApp AI reply failed", error);
          await supabase.from("whatsapp_inbox").update({ processing_status: "failed" }).eq("wa_message_id", message.id);
        }
      }
    }
  }
  return json({ received: true, stored, replied });
});
