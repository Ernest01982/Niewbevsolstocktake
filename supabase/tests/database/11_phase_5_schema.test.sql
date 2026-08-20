begin;
create extension if not exists pgtap with schema extensions;
select plan(29);

select has_table('public', 'recognition_events', 'recognition events exists');
select has_type('public', 'recognition_confidence_tier', 'recognition confidence tier exists');
select has_type('public', 'recognition_selection_method', 'recognition selection method exists');
select has_type('public', 'recognition_media_status', 'recognition media status exists');
select has_column('public', 'company_settings', 'recognition_high_confidence', 'company settings carry high threshold');
select has_column('public', 'company_settings', 'recognition_medium_confidence', 'company settings carry medium threshold');
select has_column('public', 'recognition_events', 'idempotency_key', 'recognition events carry idempotency keys');
select has_column('public', 'recognition_events', 'candidate_products', 'candidate products are logged');
select has_column('public', 'recognition_events', 'media_expires_at', 'media deletion deadline is tracked');
select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.recognition_events'::regclass),
  'recognition events has enabled and forced RLS'
);
select has_index('public', 'recognition_events', 'recognition_events_idempotency_key_key', 'recognition idempotency key is unique');
select has_index('public', 'recognition_events', 'recognition_events_cleanup_due_idx', 'cleanup work is indexed');
select has_index('public', 'recognition_events', 'recognition_events_session_scope_idx', 'session foreign key is covered');
select has_index('public', 'recognition_events', 'recognition_events_selected_product_company_idx', 'selected product foreign key is covered');
select is(
  (select recognition_high_confidence::text from public.company_settings where company_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  '0.8500',
  'default high confidence is explicit'
);
select is(
  (select recognition_medium_confidence::text from public.company_settings where company_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  '0.5500',
  'default medium confidence is explicit'
);
select throws_ok(
  $$update public.company_settings set recognition_medium_confidence = 0.9, recognition_high_confidence = 0.8 where company_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$$,
  '23514',
  'new row for relation "company_settings" violates check constraint "company_settings_recognition_thresholds_check"',
  'medium threshold must remain below high threshold'
);
select is((select public from storage.buckets where id = 'recognition-media'), false, 'recognition media bucket is private');
select is((select file_size_limit from storage.buckets where id = 'recognition-media'), 8388608::bigint, 'recognition media bucket is limited to 8 MB');

update public.stock_takes set status = 'READY' where id = 'a4000000-0000-4000-8000-000000000001';
update public.stock_takes set status = 'ACTIVE' where id = 'a4000000-0000-4000-8000-000000000001';
insert into public.stock_taker_sessions (id, company_id, warehouse_id, stock_take_id, user_id)
values ('a8000000-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000030');
insert into public.recognition_events (
  id, idempotency_key, company_id, warehouse_id, stock_take_id,
  stock_taker_session_id, user_id, provider, model, confidence,
  confidence_tier, candidate_products, captured_at
) values (
  'ad000000-0000-4000-8000-000000000001','ad100000-0000-4000-8000-000000000001',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001',
  'a4000000-0000-4000-8000-000000000001','a8000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000030','test','test-model',0.9,'HIGH',
  '[{"product_id":"a3000000-0000-4000-8000-000000000001","confidence":0.9}]',now()
);
select throws_ok(
  $$update public.recognition_events set model = 'changed' where id = 'ad000000-0000-4000-8000-000000000001'$$,
  '55000',
  'recognition_events rows may only be changed by controlled operations.',
  'recognition events reject direct updates'
);
select throws_ok(
  $$delete from public.recognition_events where id = 'ad000000-0000-4000-8000-000000000001'$$,
  '55000',
  'recognition_events rows may only be changed by controlled operations.',
  'recognition events reject deletes'
);
select ok(has_function_privilege('authenticated', 'public.record_recognition_event(jsonb)', 'EXECUTE'), 'authenticated can record recognition events');
select ok(has_function_privilege('authenticated', 'public.sync_recognition_events_batch(jsonb)', 'EXECUTE'), 'authenticated can sync recognition events');
select ok(not has_function_privilege('authenticated', 'public.claim_recognition_media_cleanup(integer)', 'EXECUTE'), 'authenticated cannot claim cleanup work');
select ok(has_function_privilege('service_role', 'public.claim_recognition_media_cleanup(integer)', 'EXECUTE'), 'service role can claim cleanup work');
select ok(not has_table_privilege('authenticated', 'public.recognition_events', 'INSERT'), 'authenticated cannot insert recognition events directly');
select ok(not has_function_privilege('authenticated', 'public.authorize_recognition_cleanup(text)', 'EXECUTE'), 'authenticated cannot verify cleanup tokens');
select ok(has_function_privilege('service_role', 'public.authorize_recognition_cleanup(text)', 'EXECUTE'), 'service role can verify cleanup tokens');
select is(
  (select schedule from cron.job where jobname = 'cleanup-expired-recognition-media'),
  '*/15 * * * *',
  'recognition media cleanup is scheduled every 15 minutes'
);

select * from finish();
rollback;
