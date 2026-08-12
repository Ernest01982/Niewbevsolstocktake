import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { Session } from '@supabase/supabase-js';
import { supabase } from '../../lib/supabase';
import {
  calculateTotalUnits,
  CountValidationError,
  parseQuantityInput,
  type CachedProduct,
  type CountQuantities,
  type CountType,
} from './count';
import {
  cacheProducts,
  countPendingRecords,
  enqueueCount,
  hasLocalDuplicate,
  recoverInterruptedCounts,
  searchCachedProducts,
} from '../offline/database';
import { syncPendingCounts } from '../offline/sync';
import { sendCountBatchToSupabase } from '../offline/supabaseSync';

type Connectivity = 'Offline' | 'Online' | 'Syncing';

interface ContextIdentity {
  id: string;
  name: string;
}

interface WarehouseIdentity extends ContextIdentity {
  code: string;
}

interface AvailableContext {
  company: ContextIdentity;
  stock_take: { id: string; status: 'ACTIVE' | 'RECOUNT' };
  warehouse: WarehouseIdentity;
}

interface ActiveSession extends AvailableContext {
  id: string;
  last_active_at: string;
  started_at: string;
  status: 'ACTIVE';
}

interface StockTakerContext {
  available_contexts: AvailableContext[];
  session: ActiveSession | null;
  success: boolean;
}

const emptyInputs = { cases: '', layers: '', pallets: '', units: '' };
const nowMs = () => Date.now();

async function refreshProductCache(companyId: string): Promise<void> {
  const pageSize = 1000;
  for (let start = 0; ; start += pageSize) {
    const { data, error } = await supabase
      .from('products')
      .select(
        'id,company_id,product_code,name,barcode,units_per_case,cases_per_layer,cases_per_pallet,updated_at',
      )
      .eq('company_id', companyId)
      .eq('status', 'active')
      .order('id')
      .range(start, start + pageSize - 1);
    if (error) throw error;
    if (data.length > 0) await cacheProducts(data);
    if (data.length < pageSize) return;
  }
}

function SignIn() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [message, setMessage] = useState('');
  const [submitting, setSubmitting] = useState(false);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setSubmitting(true);
    setMessage('');
    const { error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });
    setSubmitting(false);
    if (error) setMessage(error.message);
  }

  return (
    <main className="auth-shell">
      <form className="auth-card" onSubmit={submit}>
        <p className="eyebrow">Secure warehouse access</p>
        <h1>Sign in</h1>
        <label>
          Email
          <input
            autoComplete="email"
            inputMode="email"
            onChange={(event) => setEmail(event.target.value)}
            required
            type="email"
            value={email}
          />
        </label>
        <label>
          Password
          <input
            autoComplete="current-password"
            onChange={(event) => setPassword(event.target.value)}
            required
            type="password"
            value={password}
          />
        </label>
        {message && <p className="error-message">{message}</p>}
        <button className="primary-button" disabled={submitting} type="submit">
          {submitting ? 'Signing in…' : 'Sign in'}
        </button>
      </form>
    </main>
  );
}

function ContextPicker({
  contexts,
  onStarted,
}: {
  contexts: AvailableContext[];
  onStarted: () => Promise<void>;
}) {
  const [message, setMessage] = useState('');
  const [starting, setStarting] = useState<string>();

  async function start(context: AvailableContext) {
    setStarting(context.stock_take.id);
    setMessage('');
    const { data, error } = await supabase.rpc('start_stock_taker_session', {
      p_company_id: context.company.id,
      p_stock_take_id: context.stock_take.id,
      p_warehouse_id: context.warehouse.id,
    });
    if (error) setMessage(error.message);
    else if (!(data as { success?: boolean }).success)
      setMessage('The warehouse session could not be started.');
    else await onStarted();
    setStarting(undefined);
  }

  return (
    <main className="auth-shell">
      <section className="auth-card">
        <p className="eyebrow">Stock Taker Home</p>
        <h1>Select warehouse</h1>
        {contexts.length === 0 ? (
          <p>
            No active stock take is available for your warehouse allocation.
          </p>
        ) : (
          <div className="context-list">
            {contexts.map((context) => (
              <button
                className="context-button"
                disabled={starting !== undefined}
                key={context.stock_take.id}
                onClick={() => void start(context)}
                type="button"
              >
                <strong>{context.warehouse.name}</strong>
                <span>
                  {context.company.name} · {context.warehouse.code}
                </span>
              </button>
            ))}
          </div>
        )}
        {message && <p className="error-message">{message}</p>}
        <button
          className="text-button"
          onClick={() => void supabase.auth.signOut()}
        >
          Sign out
        </button>
      </section>
    </main>
  );
}

function ConnectivityBadge({
  state,
  pending,
}: {
  pending: number;
  state: Connectivity;
}) {
  return (
    <div
      aria-live="polite"
      className={`connectivity connectivity-${state.toLowerCase()}`}
    >
      <span aria-hidden="true" className="status-dot" />
      <span>{state}</span>
      {pending > 0 && <span>· {pending} pending</span>}
    </div>
  );
}

function CountingScreen({ active }: { active: ActiveSession }) {
  const [connectivity, setConnectivity] = useState<Connectivity>(
    navigator.onLine ? 'Online' : 'Offline',
  );
  const [pending, setPending] = useState(0);
  const [query, setQuery] = useState('');
  const [products, setProducts] = useState<CachedProduct[]>([]);
  const [selectedProduct, setSelectedProduct] = useState<CachedProduct>();
  const [countType, setCountType] = useState<CountType>('BULK');
  const [inputs, setInputs] = useState(emptyInputs);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');
  const [duplicateWarning, setDuplicateWarning] = useState(false);
  const countStartedAt = useRef<number | null>(null);

  const refreshPending = useCallback(async () => {
    setPending(await countPendingRecords());
  }, []);

  const synchronize = useCallback(async () => {
    if (!navigator.onLine) {
      setConnectivity('Offline');
      await refreshPending();
      return;
    }
    setConnectivity('Syncing');
    await syncPendingCounts(sendCountBatchToSupabase);
    setConnectivity(navigator.onLine ? 'Online' : 'Offline');
    await refreshPending();
  }, [refreshPending]);

  useEffect(() => {
    let cancelled = false;
    async function prepareOfflineData() {
      await recoverInterruptedCounts();
      await refreshPending();
      if (navigator.onLine) {
        try {
          await refreshProductCache(active.company.id);
        } catch {
          // A previously cached product master remains usable when refresh fails.
        }
        if (!cancelled) await synchronize();
      }
    }
    void prepareOfflineData();

    const online = () => void synchronize();
    const offline = () => setConnectivity('Offline');
    window.addEventListener('online', online);
    window.addEventListener('offline', offline);
    const interval = window.setInterval(() => void synchronize(), 15_000);
    return () => {
      cancelled = true;
      window.clearInterval(interval);
      window.removeEventListener('online', online);
      window.removeEventListener('offline', offline);
    };
  }, [active.company.id, refreshPending, synchronize]);

  useEffect(() => {
    let cancelled = false;
    const timer = window.setTimeout(async () => {
      const matches = await searchCachedProducts(active.company.id, query);
      if (!cancelled) setProducts(matches);
    }, 100);
    return () => {
      cancelled = true;
      window.clearTimeout(timer);
    };
  }, [active.company.id, query]);

  useEffect(() => {
    if (!selectedProduct) return;
    void hasLocalDuplicate(
      active.stock_take.id,
      selectedProduct.id,
      countType,
    ).then(setDuplicateWarning);
  }, [active.stock_take.id, countType, selectedProduct]);

  const totalPreview = useMemo(() => {
    if (!selectedProduct) return undefined;
    try {
      const quantities = Object.fromEntries(
        Object.entries(inputs).map(([key, value]) => [
          key,
          parseQuantityInput(value),
        ]),
      ) as unknown as CountQuantities;
      return calculateTotalUnits(selectedProduct, quantities);
    } catch {
      return undefined;
    }
  }, [inputs, selectedProduct]);

  function chooseProduct(product: CachedProduct) {
    setSelectedProduct(product);
    setQuery('');
    setProducts([]);
    setInputs(emptyInputs);
    setError('');
    setMessage('');
    setDuplicateWarning(false);
    countStartedAt.current = nowMs();
  }

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setError('');
    if (!selectedProduct) return;
    if (!Object.values(inputs).some((value) => value.trim() !== '')) {
      setError(
        'Enter at least one quantity. Enter 0 explicitly for zero physical stock.',
      );
      return;
    }
    try {
      const quantities = Object.fromEntries(
        Object.entries(inputs).map(([key, value]) => [
          key,
          parseQuantityInput(value),
        ]),
      ) as unknown as CountQuantities;
      const totalUnits = calculateTotalUnits(selectedProduct, quantities);
      await enqueueCount({
        ...quantities,
        company_id: active.company.id,
        count_type: countType,
        created_at: new Date().toISOString(),
        duration_ms:
          countStartedAt.current === null
            ? null
            : nowMs() - countStartedAt.current,
        idempotency_key: crypto.randomUUID(),
        product_id: selectedProduct.id,
        product_name: selectedProduct.name,
        stock_take_id: active.stock_take.id,
        stock_taker_session_id: active.id,
        total_units: totalUnits,
        warehouse_id: active.warehouse.id,
      });
      setMessage(
        `${selectedProduct.name}: ${totalUnits.toLocaleString()} units saved locally.`,
      );
      setSelectedProduct(undefined);
      setInputs(emptyInputs);
      setQuery('');
      setDuplicateWarning(false);
      await refreshPending();
      if (navigator.onLine) void synchronize();
    } catch (caught) {
      setError(
        caught instanceof CountValidationError
          ? caught.message
          : 'This count could not be saved locally. Do not move on; try again.',
      );
    }
  }

  return (
    <main className="count-shell">
      <header className="count-header">
        <div>
          <p className="eyebrow">{active.warehouse.code}</p>
          <h1>Count stock</h1>
          <p>{active.warehouse.name}</p>
        </div>
        <ConnectivityBadge pending={pending} state={connectivity} />
      </header>

      {message && <div className="success-banner">{message}</div>}

      {!selectedProduct ? (
        <section className="count-card">
          <p className="step-label">Next product</p>
          <h2>Search the product cache</h2>
          <p className="muted-copy">
            Camera recognition arrives in Phase 5. Typed search works offline
            now.
          </p>
          <label className="search-label">
            Product code, name or barcode
            <input
              autoFocus
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Start typing…"
              type="search"
              value={query}
            />
          </label>
          <div className="product-results">
            {products.map((product) => (
              <button
                key={product.id}
                onClick={() => chooseProduct(product)}
                type="button"
              >
                <strong>{product.name}</strong>
                <span>
                  {product.product_code}
                  {product.barcode ? ` · ${product.barcode}` : ''}
                </span>
              </button>
            ))}
          </div>
        </section>
      ) : (
        <form className="count-card" onSubmit={submit}>
          <button
            className="back-button"
            onClick={() => setSelectedProduct(undefined)}
            type="button"
          >
            ← Change product
          </button>
          <p className="step-label">Confirmed product</p>
          <h2>{selectedProduct.name}</h2>
          <p className="product-code">{selectedProduct.product_code}</p>

          <fieldset className="segmented-control">
            <legend>Count type</legend>
            {(['BULK', 'PICK_FACE'] as const).map((type) => (
              <label key={type}>
                <input
                  checked={countType === type}
                  name="count-type"
                  onChange={() => setCountType(type)}
                  type="radio"
                />
                <span>{type === 'BULK' ? 'Bulk' : 'Pick Face'}</span>
              </label>
            ))}
          </fieldset>

          {duplicateWarning && (
            <div className="warning-banner">
              This product already has a{' '}
              {countType === 'BULK' ? 'Bulk' : 'Pick Face'} count. Continue only
              if this is another valid physical count.
            </div>
          )}

          <div className="quantity-grid">
            {(['pallets', 'layers', 'cases', 'units'] as const).map((field) => (
              <label key={field}>
                <span>{field[0]!.toUpperCase() + field.slice(1)}</span>
                <input
                  aria-label={field}
                  inputMode="numeric"
                  min="0"
                  onChange={(event) =>
                    setInputs((current) => ({
                      ...current,
                      [field]: event.target.value,
                    }))
                  }
                  pattern="[0-9]*"
                  placeholder="0"
                  type="number"
                  value={inputs[field]}
                />
              </label>
            ))}
          </div>

          <div className="total-panel">
            <span>Total units</span>
            <strong>
              {totalPreview === undefined ? '—' : totalPreview.toLocaleString()}
            </strong>
          </div>
          {error && <p className="error-message">{error}</p>}
          <button className="primary-button submit-count" type="submit">
            Save count &amp; next product
          </button>
        </form>
      )}
    </main>
  );
}

export function StockTakerApp() {
  const [session, setSession] = useState<Session | null | undefined>(undefined);
  const [context, setContext] = useState<StockTakerContext>();
  const [error, setError] = useState('');

  const loadContext = useCallback(async () => {
    const { data, error: contextError } = await supabase.rpc(
      'get_stock_taker_context',
    );
    if (contextError) {
      setError(contextError.message);
      return;
    }
    setContext(data as unknown as StockTakerContext);
  }, []);

  useEffect(() => {
    void supabase.auth
      .getSession()
      .then(({ data }) => setSession(data.session));
    const { data } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession);
      setContext(undefined);
    });
    return () => data.subscription.unsubscribe();
  }, []);

  useEffect(() => {
    if (session) queueMicrotask(() => void loadContext());
  }, [loadContext, session]);

  if (session === undefined)
    return <main className="loading-shell">Recovering secure session…</main>;
  if (!session) return <SignIn />;
  if (error)
    return <main className="loading-shell error-message">{error}</main>;
  if (!context)
    return <main className="loading-shell">Loading warehouse context…</main>;
  if (!context.session)
    return (
      <ContextPicker
        contexts={context.available_contexts}
        onStarted={loadContext}
      />
    );
  return <CountingScreen active={context.session} />;
}
