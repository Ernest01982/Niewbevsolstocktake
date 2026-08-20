create or replace function private.normalize_recognition_candidates(
  target_company_id uuid,
  raw_candidates jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  candidate jsonb;
  candidate_product_id uuid;
  candidate_confidence numeric;
  normalized jsonb := '[]'::jsonb;
  seen_ids uuid[] := '{}'::uuid[];
begin
  if raw_candidates is null then
    return normalized;
  end if;
  if jsonb_typeof(raw_candidates) <> 'array' or jsonb_array_length(raw_candidates) > 3 then
    raise exception 'Candidate products must be an array containing at most three products.'
      using errcode = '22023';
  end if;
  for candidate in select value from jsonb_array_elements(raw_candidates)
  loop
    if jsonb_typeof(candidate) <> 'object' then
      raise exception 'Each recognition candidate must be an object.'
        using errcode = '22023';
    end if;
    begin
      candidate_product_id := (candidate ->> 'product_id')::uuid;
      candidate_confidence := (candidate ->> 'confidence')::numeric;
    exception when others then
      raise exception 'Recognition candidate identity or confidence is invalid.'
        using errcode = '22023';
    end;
    if candidate_product_id is null or candidate_confidence is null
      or candidate_confidence < 0 or candidate_confidence > 1 then
      raise exception 'Recognition candidate confidence must be between zero and one.'
        using errcode = '22023';
    end if;
    if candidate_product_id = any(seen_ids) then
      raise exception 'Recognition candidates must be unique.'
        using errcode = '22023';
    end if;
    if not exists (
      select 1 from public.products
      where id = candidate_product_id and company_id = target_company_id and status = 'active'
    ) then
      raise exception 'Recognition candidate is not an active company product.'
        using errcode = '22023';
    end if;
    seen_ids := array_append(seen_ids, candidate_product_id);
    normalized := normalized || jsonb_build_array(jsonb_build_object(
      'product_id', candidate_product_id,
      'confidence', round(candidate_confidence, 4)
    ));
  end loop;
  select coalesce(
    jsonb_agg(value order by (value ->> 'confidence')::numeric desc),
    '[]'::jsonb
  )
  into normalized
  from jsonb_array_elements(normalized);
  return normalized;
end;
$$;

revoke all on function private.normalize_recognition_candidates(uuid, jsonb)
from public, anon, authenticated;
