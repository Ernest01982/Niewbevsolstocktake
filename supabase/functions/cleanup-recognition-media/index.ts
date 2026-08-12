import '@supabase/functions-js/edge-runtime.d.ts';
import { withSupabase } from '@supabase/server';

interface CleanupItem {
  bucket: string;
  path: string;
  recognition_event_id: string;
}

export default {
  fetch: withSupabase({ auth: 'none' }, async (request, context) => {
    if (request.method !== 'POST') {
      return Response.json(
        {
          error: {
            code: 'method_not_allowed',
            message: 'Use POST for cleanup.',
          },
          success: false,
        },
        { status: 405 },
      );
    }
    const cleanupToken = request.headers.get('x-cleanup-token');
    const { data: authorised, error: authorisationError } =
      await context.supabaseAdmin.rpc('authorize_recognition_cleanup', {
        p_token: cleanupToken,
      });
    if (authorisationError || authorised !== true) {
      return Response.json(
        {
          error: {
            code: 'unauthorised_cleanup',
            message: 'Cleanup authentication failed.',
          },
          success: false,
        },
        { status: 401 },
      );
    }
    let limit = 100;
    try {
      const body = await request.json();
      if (body?.limit !== undefined) limit = Number(body.limit);
    } catch {
      // An empty request body uses the bounded default.
    }
    if (!Number.isInteger(limit) || limit < 1 || limit > 500) {
      return Response.json(
        {
          error: {
            code: 'invalid_limit',
            message: 'Cleanup limit must be between 1 and 500.',
          },
          success: false,
        },
        { status: 400 },
      );
    }

    const { data: claimResult, error: claimError } =
      await context.supabaseAdmin.rpc('claim_recognition_media_cleanup', {
        p_limit: limit,
      });
    if (claimError) {
      return Response.json(
        {
          error: { code: 'claim_failed', message: claimError.message },
          success: false,
        },
        { status: 500 },
      );
    }
    const items = (claimResult as { items?: CleanupItem[] })?.items ?? [];
    let deleted = 0;
    let failed = 0;
    for (const item of items) {
      const removal = await context.supabaseAdmin.storage
        .from(item.bucket)
        .remove([item.path]);
      const completion = await context.supabaseAdmin.rpc(
        'complete_recognition_media_cleanup',
        {
          p_error: removal.error?.message ?? null,
          p_recognition_event_id: item.recognition_event_id,
          p_success: !removal.error,
        },
      );
      if (removal.error || completion.error) failed += 1;
      else deleted += 1;
    }
    return Response.json({
      failed,
      processed: items.length,
      success: failed === 0,
      deleted,
    });
  }),
};
