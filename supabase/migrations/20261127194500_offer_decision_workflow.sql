create or replace function public.respond_to_offer(p_offer_id uuid,p_decision text)
returns void language plpgsql security invoker set search_path = '' as $$
declare v_request_id uuid; v_request_org_id uuid; v_request_status text;
begin
 if (select auth.uid()) is null then raise exception 'Sign in is required'; end if;
 if p_decision not in ('accepted','rejected') then raise exception 'Invalid offer decision'; end if;
 select o.request_id into v_request_id from public.offers o where o.id=p_offer_id;
 if v_request_id is null then raise exception 'Offer not found'; end if;
 select r.organization_id,r.status into v_request_org_id,v_request_status from public.service_requests r where r.id=v_request_id for update;
 if v_request_org_id is null then raise exception 'Request not found'; end if;
 if not private.has_org_role(v_request_org_id,array['owner','admin','manager']) then raise exception 'Only the request owner team can decide on offers'; end if;
 if v_request_status<>'open' then raise exception 'This request is no longer open'; end if;
 update public.offers set status=p_decision,updated_at=now() where id=p_offer_id and status='submitted';
 if not found then raise exception 'This offer has already been processed'; end if;
 if p_decision='accepted' then
  update public.service_requests set status='in_progress',updated_at=now() where id=v_request_id and status='open';
  update public.offers set status='rejected',updated_at=now() where request_id=v_request_id and id<>p_offer_id and status='submitted';
 end if;
end; $$;
revoke all on function public.respond_to_offer(uuid,text) from public,anon;
grant execute on function public.respond_to_offer(uuid,text) to authenticated;