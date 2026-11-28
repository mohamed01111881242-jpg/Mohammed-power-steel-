// Customer dashboard: private requests, received offers and post-completion reviews.
document.addEventListener('DOMContentLoaded', function () {
  if (!db) return;
  var workspace = document.getElementById('customerWorkspace');
  var host = document.getElementById('customerRequests');
  var status = document.getElementById('customerWorkspaceStatus');
  function escCustomer(v) { return String(v == null ? '' : v).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/\"/g, '&quot;').replace(/'/g, '&#39;'); }
  function phoneDigits(v) { return String(v || '').replace(/\D/g, ''); }
  async function loadWorkspace() {
    if (!user) { workspace.classList.add('hidden'); return; }
    workspace.classList.remove('hidden'); status.textContent = 'جارٍ تحميل طلباتك والعروض...';
    var mr = await db.from('memberships').select('organization_id,organizations!inner(account_type)').eq('user_id', user.id).eq('organizations.account_type', 'customer');
    if (mr.error) { status.textContent = 'تعذر تحميل حساب العميل: ' + mr.error.message; return; }
    var orgIds = (mr.data || []).map(function(x){ return x.organization_id; });
    if (!orgIds.length) { host.innerHTML = '<div class=\"empty\">لم تنشر طلبات بعد. أول طلب تنشره سيظهر هنا.</div>'; status.textContent = ''; return; }
    var rr = await db.from('service_requests').select('id,title,request_type,details,city,status,created_at').in('organization_id', orgIds).order('created_at', {ascending:false});
    if (rr.error) { status.textContent = 'تعذر تحميل الطلبات: ' + rr.error.message; return; }
    var reqs = rr.data || [];
    if (!reqs.length) { host.innerHTML = '<div class=\"empty\">لم تنشر طلبات بعد. ابدأ بنشر أول طلب.</div>'; status.textContent = ''; return; }
    var ids = reqs.map(function(x){ return x.id; });
    var ofr = await db.from('offers').select('id,request_id,provider_organization_id,price,details,estimated_days,status,created_at,provider:organizations!offers_provider_organization_id_fkey(name,phone,whatsapp_phone)').in('request_id', ids).order('created_at', {ascending:false});
    var rev = await db.from('provider_reviews').select('request_id').eq('reviewer_user_id', user.id);
    if (ofr.error) { status.textContent = 'تعذر تحميل العروض: ' + ofr.error.message; return; }
    var offerIds=(ofr.data||[]).map(function(x){return x.id;});
    var sessionResult=offerIds.length?await db.from('negotiation_sessions').select('id,offer_id,status').in('offer_id',offerIds):{data:[],error:null};
    var sessions=sessionResult.data||[];var sessionIds=sessions.map(function(x){return x.id;});
    var messageResult=sessionIds.length?await db.from('negotiation_messages').select('id,session_id,sender_type,body,created_at').in('session_id',sessionIds).order('created_at',{ascending:true}):{data:[],error:null};
    var agreementResult=sessionIds.length?await db.from('deal_agreements').select('id,session_id,final_terms,status').in('session_id',sessionIds):{data:[],error:null};
    var reviewed = new Set((rev.data || []).map(function(x){ return x.request_id; }));
    host.innerHTML = reqs.map(function(r){
      var list = (ofr.data || []).filter(function(o){ return o.request_id === r.id; });
      var label = ({open:'بانتظار العروض',in_progress:'جاري التنفيذ',completed:'مكتمل',cancelled:'ملغي',draft:'مسودة'})[r.status] || r.status;
      var offerHtml = list.length ? list.map(function(o){
        var provider = o.provider || {};
        var session=(sessions||[]).find(function(x){return x.offer_id===o.id;});
        var thread=session?(messageResult.data||[]).filter(function(x){return x.session_id===session.id;}):[];
        var agreement=session?(agreementResult.data||[]).find(function(x){return x.session_id===session.id;}):null;
        var negotiation= session ? '<div class=\"notice\"><strong>المفاوض الذكي</strong><p class=\"muted\">'+(thread.length?thread.map(function(m){return '<p><b>'+({customer:'العميل',provider:'مقدم الخدمة',ai:'المفاوض الذكي',system:'النظام'}[m.sender_type]||'رسالة')+':</b> '+escCustomer(m.body)+'</p>';}).join(''):'ابدأ التفاوض على السعر والمواصفات والمدة.')+'</p>'+(agreement?'<p>الشروط المقترحة: '+escCustomer(JSON.stringify(agreement.final_terms))+'</p><p>حالة الاتفاق: '+escCustomer(agreement.status)+'</p>'+(agreement.status!==\'agreed\'&&agreement.status!==\'rejected\'?'<button type=\"button\" class=\"light\" data-approve-agreement=\"'+escCustomer(agreement.id)+'\">أوافق على الشروط النهائية</button>':''):'')+(session.status!==\'agreed\'&&session.status!==\'cancelled\'?'<form data-negotiation-form=\"'+escCustomer(session.id)+'\"><input name=\"message\" required maxlength=\"4000\" placeholder=\"اكتب للمفاوض الذكي...\"><button type=\"submit\">إرسال</button></form>':'')+'</div>' : '';
        var contact = provider.whatsapp_phone || provider.phone;
        var link = contact ? '<a target=\"_blank\" rel=\"noopener\" href=\"https://wa.me/' + phoneDigits(contact) + '\">تواصل واتساب</a>' : '';
        var accept = o.status === 'submitted' && r.status === 'open' ? '<button type=\"button\" class=\"light\" data-accept-offer=\"' + escCustomer(o.id) + '\">اقبل العرض</button>' : '';
        return '<div class=\"card\" style=\"margin:8px 0\"><strong>' + escCustomer(provider.name || 'مقدم خدمة') + '</strong><p>' + escCustomer(o.price == null ? 'السعر غير محدد' : o.price) + ' جنيه · ' + (o.estimated_days ? escCustomer(o.estimated_days) + ' يوم' : 'المدة حسب الاتفاق') + '</p><p class=\"muted\">' + escCustomer(o.details) + '</p><span class=\"pill\">' + ({submitted:'عرض جديد',accepted:'عرض مقبول',rejected:'مرفوض',withdrawn:'مسحوب'}[o.status] || escCustomer(o.status)) + '</span> ' + link + ' ' + accept + negotiation + '</div>';
      }).join('') : '<p class=\"muted\">لسه مفيش عروض على الطلب ده.</p>';
      var complete = r.status === 'in_progress' ? '<button type=\"button\" class=\"light\" data-complete-request=\"' + escCustomer(r.id) + '\">تأكيد إتمام الخدمة</button>' : '';
      var accepted = list.filter(function(o){ return o.status === 'accepted'; });
      var review = r.status === 'completed' && !reviewed.has(r.id) ? accepted.map(function(o){ return '<form class=\"formgrid\" data-review-form=\"' + escCustomer(r.id) + '\" data-provider=\"' + escCustomer(o.provider_organization_id) + '\"><div class=\"field\"><label>تقييم مقدم الخدمة</label><select name=\"rating\" required><option value=\"\">اختر النجوم</option><option value=\"5\">★★★★★ ممتاز</option><option value=\"4\">★★★★ جيد جدًا</option><option value=\"3\">★★★ جيد</option><option value=\"2\">★★ مقبول</option><option value=\"1\">★ يحتاج تحسين</option></select></div><div class=\"field\"><label>اكتب تجربتك</label><input name=\"review_text\" maxlength=\"1200\" placeholder=\"رأيك يساعد العملاء الآخرين\"></div><div class=\"field full\"><button type=\"submit\">إرسال التقييم للمراجعة</button></div></form>'; }).join('') : '';
      return '<article class=\"card\" style=\"margin:12px 0\"><div style=\"display:flex;justify-content:space-between;gap:10px;flex-wrap:wrap\"><strong>' + escCustomer(r.title || r.request_type) + '</strong><span class=\"pill\">' + label + '</span></div><p>' + escCustomer(r.details) + '</p><p class=\"muted\">📍 ' + escCustomer(r.city || '') + ' · ' + new Date(r.created_at).toLocaleDateString('ar-EG') + '</p><div>' + offerHtml + '</div>' + complete + review + '</article>';
    }).join('');
    status.textContent = 'تم تحميل ' + reqs.length + ' طلبات.';
  }
  async function actionClick(e) {
    var accept = e.target.closest('[data-accept-offer]');
    if (accept) { accept.disabled = true; var a = await db.rpc('respond_to_offer', {p_offer_id:accept.dataset.acceptOffer,p_decision:'accepted'}); if (a.error) { alert('تعذر قبول العرض: ' + a.error.message); accept.disabled = false; return; } await loadWorkspace(); return; }
    var approve = e.target.closest('[data-approve-agreement]');
    if (approve) { if (!confirm('هل توافق على جميع الشروط النهائية؟ لا يكتمل الاتفاق إلا بموافقة الطرف الآخر أيضًا.')) return; var ap=await db.rpc('approve_negotiated_agreement',{p_agreement_id:approve.dataset.approveAgreement}); if(ap.error){alert('تعذر تسجيل الموافقة: '+ap.error.message);return;} alert(ap.data==='agreed'?'تم الاتفاق النهائي بموافقة الطرفين.':'تم تسجيل موافقتك وننتظر الطرف الآخر.'); await loadWorkspace(); return; }
    var complete = e.target.closest('[data-complete-request]');
    if (complete) { if (!confirm('هل انتهت الخدمة بالفعل؟ سيتم فتح التقييم بعد التأكيد.')) return; var c = await db.from('service_requests').update({status:'completed',updated_at:new Date().toISOString()}).eq('id', complete.dataset.completeRequest); if (c.error) { alert('تعذر إكمال الطلب: ' + c.error.message); return; } await loadWorkspace(); }
  }
  async function submitReview(e) {
    var form = e.target.closest('[data-review-form]'); if (!form) return; e.preventDefault();
    var d = new FormData(form); var result = await db.from('provider_reviews').insert({request_id:form.dataset.reviewForm,provider_organization_id:form.dataset.provider,reviewer_user_id:user.id,rating:Number(d.get('rating')),review_text:String(d.get('review_text') || '').trim(),is_approved:false});
    if (result.error) { alert('لم يتم إرسال التقييم: ' + result.error.message); return; }
    alert('وصل تقييمك لإدارة المنصة للمراجعة قبل نشره. شكرًا لمساعدتنا في بناء الثقة.'); await loadWorkspace();
  }
  document.getElementById('refreshCustomerWorkspace').addEventListener('click', loadWorkspace);
  host.addEventListener('click', actionClick); host.addEventListener('submit', submitReview); host.addEventListener('submit', submitNegotiation);
  document.getElementById('requestForm').addEventListener('submit', function(){ window.setTimeout(loadWorkspace, 1800); });
  db.auth.onAuthStateChange(function(event, session){ user = session && session.user ? session.user : null; if (user) loadWorkspace(); else workspace.classList.add('hidden'); });
  db.auth.getSession().then(function(result){ user = result.data.session ? result.data.session.user : null; if (user) loadWorkspace(); });
});
