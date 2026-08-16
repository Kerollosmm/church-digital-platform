do $$
declare v_user uuid; v_video bigint; v_res jsonb; v_pay bigint;
begin
  select id into v_user from public.users where role='USER' order by id limit 1;
  insert into public.videos (title_ar, event_date, yt_url, price, privacy, expires_after_days, tenant_id)
  values ('عظة المولد', now() - interval '10 days', 'https://youtu.be/abc123', 30, 'UNLISTED', 30, public.tenant_id())
  returning id into v_video;

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_user, 'role','authenticated')::text, true);
  -- UNLISTED is invisible until purchased: listing policy hides the row entirely
  if exists (select 1 from public.videos where id = v_video)
  then raise exception 'FAIL: UNLISTED video must be hidden pre-purchase'; end if;
  select public.purchase_video(v_video) into v_res;
  v_pay := (v_res->>'payment_id')::bigint;
  if v_pay is null then raise exception 'FAIL: purchase_video must return payment id'; end if;

  reset role;
  perform set_config('request.jwt.claims', null, true);
  if (select status::text from public.payments where id = v_pay) not in ('CREATED', 'PENDING')
  then raise exception 'FAIL: purchase payment must start CREATED or PENDING'; end if;
  if not exists (select 1 from public.video_purchases where video_id = v_video and user_id = v_user and payment_id = v_pay)
  then raise exception 'FAIL: video_purchases row must exist'; end if;
  if (select access_granted_at from public.video_purchases where payment_id = v_pay) is not null
  then raise exception 'FAIL: access must NOT be granted before payment'; end if;

  -- webhook lands: apply_video_payment sets access + enqueues payment_received with yt_url link
  perform public.apply_video_payment(v_pay);
  if (select status from public.payments where id = v_pay) <> 'PAID'
  then raise exception 'FAIL: payment must be PAID'; end if;
  if (select access_granted_at from public.video_purchases where payment_id = v_pay) is null
  then raise exception 'FAIL: access_granted_at must be set after payment'; end if;
  if not exists (select 1 from public.event_outbox
                 where handler_type = 'WHATSAPP'
                   and payload->>'template_name' = 'payment_received'
                   and (payload->>'link' = 'https://youtu.be/abc123' or payload->'params'->>'link' = 'https://youtu.be/abc123'))
  then raise exception 'FAIL: payment_received template with yt link must be enqueued'; end if;

  -- after purchase the buyer sees the row AND its yt_url via v_my_videos only
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_user, 'role','authenticated')::text, true);
  if (select yt_url from public.v_my_videos where id = v_video) <> 'https://youtu.be/abc123'
  then raise exception 'FAIL: buyer must read yt_url via v_my_videos after payment'; end if;
end $$;
do $$
declare v_anon_visible int; v_unlisted_hidden int;
begin
  reset role;
  insert into public.videos (title_ar, event_date, yt_url, price, privacy, tenant_id)
  values ('بث مجاني', now(), 'https://youtu.be/free1', 0, 'PUBLIC', public.tenant_id());
  set local role anon;
  select count(*) into v_anon_visible from public.videos where privacy = 'PUBLIC';
  if v_anon_visible < 1 then raise exception 'FAIL: anon must read PUBLIC videos'; end if;
  select count(*) into v_unlisted_hidden from public.videos where privacy = 'UNLISTED';
  if v_unlisted_hidden <> 0 then raise exception 'FAIL: anon must not read UNLISTED videos'; end if;
end $$;
