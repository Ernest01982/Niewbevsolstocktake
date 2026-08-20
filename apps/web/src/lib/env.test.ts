import { describe, expect, it } from 'vitest';
import { parsePublicEnvironment } from './env';

const validEnvironment = {
  VITE_SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_example',
  VITE_SUPABASE_URL: 'https://example.supabase.co',
};

describe('parsePublicEnvironment', () => {
  it('returns a normalized valid public configuration', () => {
    expect(parsePublicEnvironment(validEnvironment)).toEqual({
      supabasePublishableKey: 'sb_publishable_example',
      supabaseUrl: 'https://example.supabase.co',
    });
  });

  it('rejects a missing value', () => {
    expect(() =>
      parsePublicEnvironment({
        VITE_SUPABASE_URL: validEnvironment.VITE_SUPABASE_URL,
      }),
    ).toThrow('VITE_SUPABASE_PUBLISHABLE_KEY');
  });

  it('rejects a malformed or insecure URL', () => {
    expect(() =>
      parsePublicEnvironment({
        ...validEnvironment,
        VITE_SUPABASE_URL: 'not-a-url',
      }),
    ).toThrow('valid URL');

    expect(() =>
      parsePublicEnvironment({
        ...validEnvironment,
        VITE_SUPABASE_URL: 'http://example.supabase.co',
      }),
    ).toThrow('HTTPS');
  });

  it('rejects secret-looking browser keys', () => {
    expect(() =>
      parsePublicEnvironment({
        ...validEnvironment,
        VITE_SUPABASE_PUBLISHABLE_KEY: 'service_role_forbidden',
      }),
    ).toThrow('must never be used in browser code');
  });
});
