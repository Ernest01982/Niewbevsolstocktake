create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

do $$
begin
  if not exists (
    select 1 from vault.secrets where name = 'recognition_cleanup_token'
  ) then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'recognition_cleanup_token',
      'Authenticates the scheduled transient recognition-media cleanup request.'
    );
  end if;
end;
$$;

create function public.authorize_recognition_cleanup(p_token text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_token is not null
    and length(p_token) = 64
    and extensions.digest(p_token, 'sha256')
      = extensions.digest(secret.decrypted_secret, 'sha256')
  from vault.decrypted_secrets as secret
  where secret.name = 'recognition_cleanup_token';
$$;

comment on function public.authorize_recognition_cleanup(text) is
  'Server-only constant-length hash comparison for the Vault-backed cleanup scheduler token.';

revoke all on function public.authorize_recognition_cleanup(text)
from public, anon, authenticated;
grant execute on function public.authorize_recognition_cleanup(text) to service_role;

select cron.schedule(
  'cleanup-expired-recognition-media',
  '*/15 * * * *',
  $schedule$
    select net.http_post(
      url := 'https://woaffibkwqxwncooirzl.supabase.co/functions/v1/cleanup-recognition-media',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-cleanup-token', (
          select decrypted_secret
          from vault.decrypted_secrets
          where name = 'recognition_cleanup_token'
        )
      ),
      body := '{"limit":100}'::jsonb,
      timeout_milliseconds := 10000
    );
  $schedule$
);
