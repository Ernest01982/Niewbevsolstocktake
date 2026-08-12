export interface RecognitionCandidate {
  confidence: number;
  product_id: string;
}

export interface RecognitionInput {
  company_id: string;
  image: Blob;
  stock_take_id: string;
  warehouse_id: string;
}

export interface RecognitionProviderResult {
  candidates: RecognitionCandidate[];
  model: string;
  provider: string;
}

export interface RecognitionProvider {
  recognize(input: RecognitionInput): Promise<RecognitionProviderResult>;
}

interface ProviderEnvironment {
  apiKey?: string;
  model?: string;
  providerName?: string;
  url?: string;
}

function normalizedCandidates(value: unknown): RecognitionCandidate[] {
  if (!Array.isArray(value)) return [];
  const seen = new Set<string>();
  return value
    .flatMap((candidate) => {
      if (!candidate || typeof candidate !== 'object') return [];
      const productId = Reflect.get(candidate, 'product_id');
      const confidence = Number(Reflect.get(candidate, 'confidence'));
      if (
        typeof productId !== 'string' ||
        productId.length === 0 ||
        !Number.isFinite(confidence) ||
        confidence < 0 ||
        confidence > 1 ||
        seen.has(productId)
      ) {
        return [];
      }
      seen.add(productId);
      return [{ confidence, product_id: productId }];
    })
    .sort((left, right) => right.confidence - left.confidence)
    .slice(0, 3);
}

class ManualFallbackProvider implements RecognitionProvider {
  async recognize(): Promise<RecognitionProviderResult> {
    return {
      candidates: [],
      model: 'none',
      provider: 'manual_fallback',
    };
  }
}

class RemoteRecognitionProvider implements RecognitionProvider {
  constructor(private readonly environment: Required<ProviderEnvironment>) {}

  async recognize(input: RecognitionInput): Promise<RecognitionProviderResult> {
    const body = new FormData();
    body.set('image', input.image, 'capture');
    body.set(
      'context',
      JSON.stringify({
        company_id: input.company_id,
        max_candidates: 3,
        stock_take_id: input.stock_take_id,
        warehouse_id: input.warehouse_id,
      }),
    );
    const response = await fetch(this.environment.url, {
      body,
      headers: { Authorization: `Bearer ${this.environment.apiKey}` },
      method: 'POST',
      signal: AbortSignal.timeout(8_000),
    });
    if (!response.ok) {
      throw new Error(`Recognition provider returned HTTP ${response.status}.`);
    }
    const payload = (await response.json()) as { candidates?: unknown };
    return {
      candidates: normalizedCandidates(payload.candidates),
      model: this.environment.model,
      provider: this.environment.providerName,
    };
  }
}

export function createRecognitionProvider(): RecognitionProvider {
  const url = Deno.env.get('RECOGNITION_PROVIDER_URL')?.trim();
  const apiKey = Deno.env.get('RECOGNITION_PROVIDER_API_KEY')?.trim();
  if (!url || !apiKey) return new ManualFallbackProvider();
  return new RemoteRecognitionProvider({
    apiKey,
    model: Deno.env.get('RECOGNITION_PROVIDER_MODEL')?.trim() || 'default',
    providerName:
      Deno.env.get('RECOGNITION_PROVIDER_NAME')?.trim() || 'remote_adapter',
    url,
  });
}
