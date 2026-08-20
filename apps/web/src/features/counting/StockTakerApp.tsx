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
  enqueueManualRecognition,
  enqueueCount,
  hasLocalDuplicate,
  recoverInterruptedRecognitions,
  recoverInterruptedCounts,
  searchCachedProducts,
} from '../offline/database';
import { syncPendingCounts } from '../offline/sync';
import { sendCountBatchToSupabase } from '../offline/supabaseSync';
import { CameraCapture } from '../recognition/CameraCapture';
import {
  confirmRecognition,
  recognizeProduct,
  syncPendingRecognitions,
  type RecognitionResult,
} from '../recognition/recognition';
import {
  ManagerApp,
  type ManagementMembership,
} from '../management/ManagerApp';

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

interface RecountProduct {
  barcode: string | null;
  cases_per_layer: number | null;
  cases_per_pallet: number | null;
  id: string;
  name: string;
  product_code: string;
  units_per_case: number | null;
}

interface RecountTask {
  claimable: boolean;
  product: RecountProduct;
  status: 'UNASSIGNED' | 'ASSIGNED' | 'CLAIMED';
  task_id: string;
}

interface RecountWorkResponse {
  success: boolean;
  tasks: RecountTask[];
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
  const [passwordVisible, setPasswordVisible] = useState(false);
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
          <span className="password-input">
            <input
              autoComplete="current-password"
              onChange={(event) => setPassword(event.target.value)}
              required
              type={passwordVisible ? 'text' : 'password'}
              value={password}
            />
            <button
              aria-label={passwordVisible ? 'Hide password' : 'Show password'}
              aria-pressed={passwordVisible}
              className="password-toggle"
              onClick={() => setPasswordVisible((visible) => !visible)}
              type="button"
            >
              {passwordVisible ? 'Hide' : 'Show'}
            </button>
          </span>
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

function RecountScreen({
  active,
  onSignOut,
}: {
  active: ActiveSession;
  onSignOut: () => Promise<void>;
}) {
  const [tasks, setTasks] = useState<RecountTask[]>([]);
  const [selectedTaskId, setSelectedTaskId] = useState('');
  const [inputs, setInputs] = useState(emptyInputs);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [signingOut, setSigningOut] = useState(false);
  const idempotencyKeys = useRef(new Map<string, string>());

  const selectedTask = tasks.find((task) => task.task_id === selectedTaskId);

  const loadWork = useCallback(async () => {
    setLoading(true);
    setError('');
    const { data, error: workError } = await supabase.rpc('get_recount_work');
    if (workError) {
      setError(workError.message);
      setLoading(false);
      return;
    }
    const work = data as unknown as RecountWorkResponse;
    if (!work.success) {
      setError('Blind recount work could not be loaded.');
      setLoading(false);
      return;
    }
    setTasks(work.tasks);
    setSelectedTaskId((current) =>
      work.tasks.some((task) => task.task_id === current)
        ? current
        : (work.tasks[0]?.task_id ?? ''),
    );
    setLoading(false);
  }, []);

  useEffect(() => {
    queueMicrotask(() => void loadWork());
  }, [loadWork]);

  const totalPreview = useMemo(() => {
    if (!selectedTask) return undefined;
    try {
      const quantities = Object.fromEntries(
        Object.entries(inputs).map(([key, value]) => [
          key,
          parseQuantityInput(value),
        ]),
      ) as unknown as CountQuantities;
      return calculateTotalUnits(selectedTask.product, quantities);
    } catch {
      return undefined;
    }
  }, [inputs, selectedTask]);

  async function claimTask() {
    if (!selectedTask) return;
    setSubmitting(true);
    setError('');
    const { data, error: claimError } = await supabase.rpc(
      'claim_recount_task',
      { p_recount_task_id: selectedTask.task_id },
    );
    const result = data as {
      error?: { message?: string };
      success?: boolean;
    } | null;
    if (claimError) setError(claimError.message);
    else if (!result?.success)
      setError(result?.error?.message ?? 'This task is no longer available.');
    else {
      setMessage('Recount task claimed. Complete the blind physical count.');
      await loadWork();
    }
    setSubmitting(false);
  }

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (!selectedTask || selectedTask.status !== 'CLAIMED') return;
    if (!navigator.onLine) {
      setError('Recount submission needs a connection. Keep this screen open.');
      return;
    }
    if (!Object.values(inputs).some((value) => value.trim() !== '')) {
      setError(
        'Enter at least one quantity, including an explicit 0 for zero stock.',
      );
      return;
    }
    setSubmitting(true);
    setError('');
    try {
      const quantities = Object.fromEntries(
        Object.entries(inputs).map(([key, value]) => [
          key,
          parseQuantityInput(value),
        ]),
      ) as unknown as CountQuantities;
      calculateTotalUnits(selectedTask.product, quantities);
      let idempotencyKey = idempotencyKeys.current.get(selectedTask.task_id);
      if (!idempotencyKey) {
        idempotencyKey = crypto.randomUUID();
        idempotencyKeys.current.set(selectedTask.task_id, idempotencyKey);
      }
      const { data, error: submitError } = await supabase.rpc(
        'submit_recount',
        {
          p_record: {
            ...quantities,
            idempotency_key: idempotencyKey,
            recount_task_id: selectedTask.task_id,
            stock_taker_session_id: active.id,
          },
        },
      );
      const result = data as {
        acknowledged?: boolean;
        error?: { message?: string };
        success?: boolean;
        total_units?: number;
      } | null;
      if (submitError) throw submitError;
      if (!result?.success || !result.acknowledged)
        throw new Error(
          result?.error?.message ?? 'The recount was not acknowledged.',
        );
      setMessage(
        `${selectedTask.product.name}: ${result.total_units?.toLocaleString() ?? '0'} units submitted.`,
      );
      idempotencyKeys.current.delete(selectedTask.task_id);
      setInputs(emptyInputs);
      setSelectedTaskId('');
      await loadWork();
    } catch (caught) {
      setError(
        caught instanceof Error
          ? caught.message
          : 'The recount could not be submitted.',
      );
    } finally {
      setSubmitting(false);
    }
  }

  async function signOut() {
    if (!navigator.onLine) {
      setError('Connect to the internet before logging out safely.');
      return;
    }
    setSigningOut(true);
    setError('');
    try {
      await onSignOut();
    } catch (caught) {
      setError(
        caught instanceof Error ? caught.message : 'Log out was unsuccessful.',
      );
      setSigningOut(false);
    }
  }

  return (
    <main className="count-shell recount-shell">
      <header className="count-header">
        <div>
          <p className="eyebrow">{active.warehouse.code} · Blind work</p>
          <h1>Recount stock</h1>
          <p>{active.warehouse.name}</p>
        </div>
        <div className="count-header-actions">
          <ConnectivityBadge
            pending={0}
            state={navigator.onLine ? 'Online' : 'Offline'}
          />
          <button
            className="secondary-button logout-button"
            disabled={signingOut}
            onClick={() => void signOut()}
            type="button"
          >
            {signingOut ? 'Logging out…' : 'Log out'}
          </button>
        </div>
      </header>
      <div className="blind-banner">
        Count what is physically present. Prior counts, system stock and
        variance are intentionally hidden.
      </div>
      {message && <div className="success-banner">{message}</div>}
      {error && <div className="error-banner">{error}</div>}
      <section className="count-card">
        <div className="section-heading">
          <div>
            <p className="step-label">Assigned or available</p>
            <h2>Recount queue</h2>
          </div>
          <button className="text-button" onClick={() => void loadWork()}>
            Refresh
          </button>
        </div>
        {loading ? (
          <p>Loading blind work…</p>
        ) : tasks.length === 0 ? (
          <div className="empty-state">
            No recount work is assigned or available right now.
          </div>
        ) : (
          <div className="recount-task-list">
            {tasks.map((task) => (
              <button
                className={task.task_id === selectedTaskId ? 'selected' : ''}
                key={task.task_id}
                onClick={() => {
                  setSelectedTaskId(task.task_id);
                  setInputs(emptyInputs);
                  setError('');
                }}
                type="button"
              >
                <span>
                  <strong>{task.product.name}</strong>
                  <small>
                    {task.product.product_code}
                    {task.product.barcode ? ` · ${task.product.barcode}` : ''}
                  </small>
                </span>
                <span className="status-chip">{task.status}</span>
              </button>
            ))}
          </div>
        )}
      </section>

      {selectedTask && (
        <form className="count-card recount-form" onSubmit={submit}>
          <p className="step-label">Full-product physical recount</p>
          <h2>{selectedTask.product.name}</h2>
          <p className="product-code">{selectedTask.product.product_code}</p>
          {selectedTask.status !== 'CLAIMED' ? (
            <button
              className="primary-button submit-count"
              disabled={submitting || !navigator.onLine}
              onClick={() => void claimTask()}
              type="button"
            >
              {submitting ? 'Claiming…' : 'Claim task & start recount'}
            </button>
          ) : (
            <>
              <div className="quantity-grid">
                {(['pallets', 'layers', 'cases', 'units'] as const).map(
                  (field) => (
                    <label key={field}>
                      <span>{field[0]!.toUpperCase() + field.slice(1)}</span>
                      <input
                        aria-label={`recount ${field}`}
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
                  ),
                )}
              </div>
              <div className="total-panel">
                <span>Total units</span>
                <strong>
                  {totalPreview === undefined
                    ? '—'
                    : totalPreview.toLocaleString()}
                </strong>
              </div>
              <button
                className="primary-button submit-count"
                disabled={submitting || !navigator.onLine}
                type="submit"
              >
                {submitting ? 'Submitting…' : 'Submit immutable recount'}
              </button>
            </>
          )}
        </form>
      )}
    </main>
  );
}

function CountingScreen({
  active,
  onSignOut,
}: {
  active: ActiveSession;
  onSignOut: () => Promise<void>;
}) {
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
  const [cameraOpen, setCameraOpen] = useState(false);
  const [recognizing, setRecognizing] = useState(false);
  const [signingOut, setSigningOut] = useState(false);
  const [recognition, setRecognition] = useState<RecognitionResult>();
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
    await Promise.all([
      syncPendingCounts(sendCountBatchToSupabase),
      syncPendingRecognitions(),
    ]);
    setConnectivity(navigator.onLine ? 'Online' : 'Offline');
    await refreshPending();
  }, [refreshPending]);

  useEffect(() => {
    let cancelled = false;
    async function prepareOfflineData() {
      await recoverInterruptedCounts();
      await recoverInterruptedRecognitions();
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

  async function chooseProduct(
    product: CachedProduct,
    recognitionMethod?: 'AUTO_PRESELECT' | 'CANDIDATE_CONFIRMATION',
  ) {
    setError('');
    try {
      if (recognition) {
        await confirmRecognition(
          recognition.recognition_event_id,
          product.id,
          recognitionMethod ?? 'MANUAL_SEARCH',
        );
      } else {
        await enqueueManualRecognition({
          candidates: [],
          captured_at: new Date().toISOString(),
          company_id: active.company.id,
          idempotency_key: crypto.randomUUID(),
          model: 'cached-products-v1',
          provider: 'offline_manual_cache',
          selected_product_id: product.id,
          selection_method: 'MANUAL_SEARCH',
          stock_take_id: active.stock_take.id,
          stock_taker_session_id: active.id,
          warehouse_id: active.warehouse.id,
        });
      }
    } catch (caught) {
      setError(
        caught instanceof Error
          ? caught.message
          : 'The product confirmation could not be saved.',
      );
      return;
    }
    setSelectedProduct(product);
    setQuery('');
    setProducts([]);
    setInputs(emptyInputs);
    setError('');
    setMessage('');
    setDuplicateWarning(false);
    setRecognition(undefined);
    countStartedAt.current = nowMs();
    await refreshPending();
    if (navigator.onLine) void synchronize();
  }

  async function captureAndRecognize(image: Blob) {
    setRecognizing(true);
    setError('');
    try {
      const result = await recognizeProduct(active.company.id, image);
      setRecognition(result);
      setCameraOpen(false);
      if (result.confidence_tier === 'LOW') {
        setMessage(
          'Confidence was low. Confirm the product with manual search.',
        );
      } else if (result.confidence_tier === 'NO_MATCH') {
        setMessage('No reliable match was found. Use manual search.');
      } else {
        setMessage('');
      }
    } catch (caught) {
      setCameraOpen(false);
      setMessage('Recognition is unavailable. Manual cached search is ready.');
      setError(caught instanceof Error ? caught.message : '');
    } finally {
      setRecognizing(false);
    }
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
      setRecognition(undefined);
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

  async function signOut() {
    if (pending > 0) {
      setError(
        `Wait for ${pending} pending ${pending === 1 ? 'item' : 'items'} to sync before logging out.`,
      );
      return;
    }
    if (!navigator.onLine) {
      setError('Connect to the internet before logging out safely.');
      return;
    }
    setSigningOut(true);
    setError('');
    try {
      await onSignOut();
    } catch (caught) {
      setError(
        caught instanceof Error ? caught.message : 'Log out was unsuccessful.',
      );
      setSigningOut(false);
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
        <div className="count-header-actions">
          <ConnectivityBadge pending={pending} state={connectivity} />
          <button
            className="secondary-button logout-button"
            disabled={signingOut}
            onClick={() => void signOut()}
            type="button"
          >
            {signingOut ? 'Logging out…' : 'Log out'}
          </button>
        </div>
      </header>

      {message && <div className="success-banner">{message}</div>}

      {!selectedProduct ? (
        <section className="count-card">
          <p className="step-label">Next product</p>
          <h2>Recognise or search</h2>
          <p className="muted-copy">
            Recognition works online. Cached product search remains available
            offline at all times.
          </p>
          <button
            className="camera-button"
            disabled={connectivity === 'Offline'}
            onClick={() => {
              setError('');
              setRecognition(undefined);
              setCameraOpen(true);
            }}
            type="button"
          >
            <span aria-hidden="true">▣</span>
            {connectivity === 'Offline'
              ? 'Camera recognition needs a connection'
              : 'Open live camera'}
          </button>
          {recognition &&
            (recognition.confidence_tier === 'HIGH' ||
              recognition.confidence_tier === 'MEDIUM') && (
              <div className="recognition-results">
                <p className="step-label">
                  {recognition.confidence_tier === 'HIGH'
                    ? 'Likely match'
                    : 'Confirm one of these'}
                </p>
                {recognition.candidates.map((candidate, index) => (
                  <button
                    className={index === 0 ? 'candidate-primary' : ''}
                    key={candidate.product.id}
                    onClick={() =>
                      void chooseProduct(
                        candidate.product,
                        recognition.confidence_tier === 'HIGH'
                          ? 'AUTO_PRESELECT'
                          : 'CANDIDATE_CONFIRMATION',
                      )
                    }
                    type="button"
                  >
                    <strong>{candidate.product.name}</strong>
                    <span>
                      {candidate.product.product_code} ·{' '}
                      {Math.round(candidate.confidence * 100)}% match
                    </span>
                  </button>
                ))}
              </div>
            )}
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
                onClick={() => void chooseProduct(product)}
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
      {cameraOpen && (
        <CameraCapture
          busy={recognizing}
          onCapture={captureAndRecognize}
          onClose={() => setCameraOpen(false)}
        />
      )}
    </main>
  );
}

export function StockTakerApp() {
  const [session, setSession] = useState<Session | null | undefined>(undefined);
  const [context, setContext] = useState<StockTakerContext>();
  const [managementMembership, setManagementMembership] = useState<
    ManagementMembership | null | undefined
  >(undefined);
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

  async function signOutStockTaker() {
    if (context?.session) {
      const { data, error: endError } = await supabase.rpc(
        'end_stock_taker_session',
        { p_session_id: context.session.id },
      );
      if (endError) throw endError;
      const result = data as {
        error?: { message?: string };
        success?: boolean;
      } | null;
      if (!result?.success) {
        throw new Error(
          result?.error?.message ?? 'The counting session could not be ended.',
        );
      }
    }
    const { error: signOutError } = await supabase.auth.signOut();
    if (signOutError) throw signOutError;
  }

  useEffect(() => {
    void supabase.auth
      .getSession()
      .then(({ data }) => setSession(data.session));
    const { data } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession);
      setContext(undefined);
      setManagementMembership(undefined);
    });
    return () => data.subscription.unsubscribe();
  }, []);

  useEffect(() => {
    if (!session) return;
    queueMicrotask(() => {
      void supabase
        .from('company_memberships')
        .select('company_id,role')
        .eq('user_id', session.user.id)
        .eq('status', 'active')
        .in('role', ['super_admin', 'admin', 'manager'])
        .limit(1)
        .maybeSingle()
        .then(({ data, error: membershipError }) => {
          if (membershipError) {
            setError(membershipError.message);
            return;
          }
          if (data) {
            setManagementMembership(data as ManagementMembership);
            return;
          }
          setManagementMembership(null);
          void loadContext();
        });
    });
  }, [loadContext, session]);

  if (session === undefined)
    return <main className="loading-shell">Recovering secure session…</main>;
  if (!session) return <SignIn />;
  if (error)
    return <main className="loading-shell error-message">{error}</main>;
  if (managementMembership === undefined)
    return <main className="loading-shell">Loading secure role…</main>;
  if (managementMembership)
    return <ManagerApp membership={managementMembership} />;
  if (!context)
    return <main className="loading-shell">Loading warehouse context…</main>;
  if (!context.session)
    return (
      <ContextPicker
        contexts={context.available_contexts}
        onStarted={loadContext}
      />
    );
  return context.session.stock_take.status === 'RECOUNT' ? (
    <RecountScreen active={context.session} onSignOut={signOutStockTaker} />
  ) : (
    <CountingScreen active={context.session} onSignOut={signOutStockTaker} />
  );
}
