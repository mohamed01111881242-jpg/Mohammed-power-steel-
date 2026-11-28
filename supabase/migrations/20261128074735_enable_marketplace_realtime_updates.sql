-- Enable realtime delivery for the customer/provider request and negotiation workflow.
alter publication supabase_realtime add table public.offers, public.service_requests, public.negotiation_messages, public.deal_agreements;
