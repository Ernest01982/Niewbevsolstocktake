export interface PublicEnvironment {
  supabasePublishableKey: string;
  supabaseUrl: string;
}

function requireValue(
  source: Record<string, string | boolean | undefined>,
  name: string,
): string {
  const value = source[name];

  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new Error(`Missing required public environment variable: ${name}`);
  }

  return value.trim();
}

export function parsePublicEnvironment(
  source: Record<string, string | boolean | undefined>,
): PublicEnvironment {
  const supabaseUrl = requireValue(source, 'VITE_SUPABASE_URL');
  const supabasePublishableKey = requireValue(
    source,
    'VITE_SUPABASE_PUBLISHABLE_KEY',
  );

  let parsedUrl: URL;

  try {
    parsedUrl = new URL(supabaseUrl);
  } catch {
    throw new Error('VITE_SUPABASE_URL must be a valid URL.');
  }

  if (parsedUrl.protocol !== 'https:') {
    throw new Error('VITE_SUPABASE_URL must use HTTPS.');
  }

  if (/service[_-]?role|secret/i.test(supabasePublishableKey)) {
    throw new Error(
      'A secret or service-role key must never be used in browser code.',
    );
  }

  return {
    supabasePublishableKey,
    supabaseUrl: parsedUrl.toString().replace(/\/$/, ''),
  };
}
