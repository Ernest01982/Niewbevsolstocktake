import '@supabase/functions-js/edge-runtime.d.ts';
import { withSupabase } from '@supabase/server';
import { createRecognitionProvider } from '../_shared/recognition-provider.ts';

const ALLOWED_MEDIA_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);
const MAX_MEDIA_BYTES = 8 * 1024 * 1024;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

interface ActiveContext {
  company: { id: string };
  id: string;
  stock_take: { id: string; status: string };
  warehouse: { id: string };
}

function extensionFor(contentType: string): string {
  if (contentType === 'image/png') return 'png';
  if (contentType === 'image/webp') return 'webp';
  return 'jpg';
}

function errorResponse(
  code: string,
  message: string,
  status: number,
): Response {
  return Response.json(
    { error: { code, message }, success: false },
    { status },
  );
}

export default {
  fetch: withSupabase({ auth: 'user' }, async (request, context) => {
    if (request.method !== 'POST') {
      return errorResponse(
        'method_not_allowed',
        'Use POST for recognition.',
        405,
      );
    }
    const userId = context.userClaims?.sub ?? context.userClaims?.id;
    if (typeof userId !== 'string') {
      return errorResponse(
        'unauthenticated',
        'Authentication is required.',
        401,
      );
    }

    let form: FormData;
    try {
      form = await request.formData();
    } catch {
      return errorResponse(
        'invalid_request',
        'Recognition requires multipart form data.',
        400,
      );
    }
    const image = form.get('image');
    const idempotencyKey = String(form.get('idempotency_key') ?? '');
    const capturedAt = String(
      form.get('captured_at') ?? new Date().toISOString(),
    );
    if (!(image instanceof File)) {
      return errorResponse(
        'image_required',
        'Capture a product image first.',
        400,
      );
    }
    if (
      !ALLOWED_MEDIA_TYPES.has(image.type) ||
      image.size < 1 ||
      image.size > MAX_MEDIA_BYTES
    ) {
      return errorResponse(
        'invalid_image',
        'Use a JPEG, PNG or WebP image no larger than 8 MB.',
        400,
      );
    }
    if (!UUID_PATTERN.test(idempotencyKey)) {
      return errorResponse(
        'invalid_idempotency_key',
        'A valid recognition identity is required.',
        400,
      );
    }

    const { data: contextResult, error: contextError } =
      await context.supabase.rpc('get_stock_taker_context');
    if (contextError) {
      return errorResponse('context_unavailable', contextError.message, 400);
    }
    const active = (contextResult as { session?: ActiveContext | null })
      ?.session;
    if (!active || active.stock_take.status !== 'ACTIVE') {
      return errorResponse(
        'recognition_closed',
        'An active stock-taker session is required.',
        409,
      );
    }

    const mediaPath = `${userId}/${idempotencyKey}/capture.${extensionFor(image.type)}`;
    const upload = await context.supabaseAdmin.storage
      .from('recognition-media')
      .upload(mediaPath, image, {
        cacheControl: '0',
        contentType: image.type,
        upsert: false,
      });
    const storedMediaPath = upload.error ? null : mediaPath;

    let providerResult;
    let providerError: string | null = null;
    try {
      providerResult = await createRecognitionProvider().recognize({
        company_id: active.company.id,
        image,
        stock_take_id: active.stock_take.id,
        warehouse_id: active.warehouse.id,
      });
    } catch (error) {
      providerError =
        error instanceof Error ? error.message : 'Recognition provider failed.';
      providerResult = {
        candidates: [],
        model: 'unavailable',
        provider: 'manual_fallback',
      };
    }

    const { data: eventResult, error: eventError } = await context.supabase.rpc(
      'record_recognition_event',
      {
        p_record: {
          candidates: providerResult.candidates,
          captured_at: capturedAt,
          company_id: active.company.id,
          idempotency_key: idempotencyKey,
          media_path: storedMediaPath,
          model: providerResult.model,
          provider: providerResult.provider,
          stock_take_id: active.stock_take.id,
          stock_taker_session_id: active.id,
          warehouse_id: active.warehouse.id,
        },
      },
    );
    const event = eventResult as {
      error?: { code?: string; message?: string };
      recognition_event_id?: string;
      success?: boolean;
    };
    if (eventError || !event?.success || !event.recognition_event_id) {
      if (storedMediaPath) {
        await context.supabaseAdmin.storage
          .from('recognition-media')
          .remove([storedMediaPath]);
      }
      return errorResponse(
        event?.error?.code ?? 'event_not_recorded',
        eventError?.message ??
          event?.error?.message ??
          'Recognition event could not be recorded.',
        400,
      );
    }

    let mediaStatus = storedMediaPath ? 'PENDING' : 'NOT_STORED';
    if (storedMediaPath) {
      const removal = await context.supabaseAdmin.storage
        .from('recognition-media')
        .remove([storedMediaPath]);
      const completion = await context.supabaseAdmin.rpc(
        'complete_recognition_media_cleanup',
        {
          p_error: removal.error?.message ?? null,
          p_recognition_event_id: event.recognition_event_id,
          p_success: !removal.error,
        },
      );
      if (!completion.error) mediaStatus = removal.error ? 'FAILED' : 'DELETED';
    }

    return Response.json({
      ...eventResult,
      manual_fallback_required:
        (eventResult as { confidence_tier?: string }).confidence_tier ===
          'LOW' ||
        (eventResult as { confidence_tier?: string }).confidence_tier ===
          'NO_MATCH',
      media_status: mediaStatus,
      provider_error: providerError,
    });
  }),
};
