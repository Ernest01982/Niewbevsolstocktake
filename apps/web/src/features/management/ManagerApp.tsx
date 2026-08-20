import { useCallback, useEffect, useMemo, useState } from 'react';
import { supabase } from '../../lib/supabase';
import type { Database } from '../../types/database.types';

type MembershipRole = Database['public']['Enums']['membership_role'];
type StockTakeStatus = Database['public']['Enums']['stock_take_status'];
type RecountTaskRow = Database['public']['Tables']['recount_tasks']['Row'];

export interface ManagementMembership {
  company_id: string;
  role: Extract<MembershipRole, 'super_admin' | 'admin' | 'manager'>;
}

interface Warehouse {
  id: string;
  name: string;
  warehouse_code: string;
}

interface StockTake {
  id: string;
  status: StockTakeStatus;
  warehouse_id: string;
}

interface ManagerProgress {
  completed_recounts: number;
  covered_products: number;
  initial_count_records: number;
  open_duplicate_flags: number;
  open_recounts: number;
  progress_percent: number;
  snapshot_products: number;
  success: boolean;
}

interface VarianceRow {
  absolute_variance_units: number;
  brand_id: string | null;
  brand_name: string | null;
  effective_threshold_units: number;
  initial_physical_units: number;
  open_duplicate_flags: number;
  physical_units: number;
  product_code: string;
  product_id: string;
  product_name: string;
  recount_required: boolean;
  recount_status: Database['public']['Enums']['recount_task_status'] | null;
  signed_variance_units: number;
  snapshot_units: number;
  threshold_source: Database['public']['Enums']['variance_threshold_source'];
}

interface VarianceResponse {
  success: boolean;
  variances: VarianceRow[];
}

interface CountFlag {
  count_id: string;
  created_at: string;
  id: string;
}

interface StockTakerOption {
  name: string;
  userId: string;
}

interface ProductThresholdDraft {
  active: boolean;
  value: string;
}

interface RpcResult {
  error?: { code?: string; message?: string };
  success?: boolean;
}

const activeStatuses: StockTakeStatus[] = [
  'ACTIVE',
  'RECOUNT',
  'REVIEW',
  'REOPENED',
];

function asMessage(result: RpcResult, fallback: string): string {
  return result.error?.message ?? fallback;
}

export function ManagerApp({
  membership,
}: {
  membership: ManagementMembership;
}) {
  const [companyName, setCompanyName] = useState('Management');
  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [stockTakes, setStockTakes] = useState<StockTake[]>([]);
  const [warehouseId, setWarehouseId] = useState('');
  const [stockTakeId, setStockTakeId] = useState('');
  const [progress, setProgress] = useState<ManagerProgress>();
  const [variances, setVariances] = useState<VarianceRow[]>([]);
  const [tasks, setTasks] = useState<RecountTaskRow[]>([]);
  const [flags, setFlags] = useState<CountFlag[]>([]);
  const [stockTakers, setStockTakers] = useState<StockTakerOption[]>([]);
  const [selectedTasks, setSelectedTasks] = useState<string[]>([]);
  const [assigneeId, setAssigneeId] = useState('');
  const [minimumVariance, setMinimumVariance] = useState('');
  const [appliedMinimumVariance, setAppliedMinimumVariance] = useState('');
  const [companyThreshold, setCompanyThreshold] = useState('0');
  const [warehouseThreshold, setWarehouseThreshold] = useState('0');
  const [warehouseThresholdActive, setWarehouseThresholdActive] =
    useState(false);
  const [productThresholds, setProductThresholds] = useState<
    Record<string, ProductThresholdDraft>
  >({});
  const [resolutionNote, setResolutionNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');

  const scopedStockTakeId = stockTakes.some(
    (stockTake) =>
      stockTake.id === stockTakeId && stockTake.warehouse_id === warehouseId,
  )
    ? stockTakeId
    : (stockTakes.find((stockTake) => stockTake.warehouse_id === warehouseId)
        ?.id ?? '');
  const selectedStockTake = stockTakes.find(
    (stockTake) => stockTake.id === scopedStockTakeId,
  );
  const selectedWarehouse = warehouses.find(
    (warehouse) => warehouse.id === warehouseId,
  );
  const canChangeThresholds =
    membership.role === 'admin' || membership.role === 'super_admin';

  const loadScope = useCallback(async () => {
    setLoading(true);
    setError('');
    const [companyResult, warehouseResult, stockTakeResult] = await Promise.all(
      [
        supabase
          .from('companies')
          .select('name')
          .eq('id', membership.company_id)
          .maybeSingle(),
        supabase
          .from('warehouses')
          .select('id,warehouse_code,name')
          .eq('company_id', membership.company_id)
          .eq('status', 'active')
          .order('name'),
        supabase
          .from('stock_takes')
          .select('id,status,warehouse_id')
          .eq('company_id', membership.company_id)
          .in('status', activeStatuses)
          .order('created_at', { ascending: false }),
      ],
    );
    const scopeError =
      companyResult.error ?? warehouseResult.error ?? stockTakeResult.error;
    if (scopeError) {
      setError(scopeError.message);
      setLoading(false);
      return;
    }
    setCompanyName(companyResult.data?.name ?? 'Management');
    setWarehouses(warehouseResult.data ?? []);
    setStockTakes(stockTakeResult.data ?? []);
    setWarehouseId((currentWarehouseId) =>
      warehouseResult.data?.some(
        (warehouse) => warehouse.id === currentWarehouseId,
      )
        ? currentWarehouseId
        : (warehouseResult.data?.[0]?.id ?? ''),
    );
    setLoading(false);
  }, [membership.company_id]);

  const refreshDashboard = useCallback(async () => {
    if (!warehouseId || !scopedStockTakeId) return;
    setLoading(true);
    setError('');
    const varianceArgs: Database['public']['Functions']['get_variances']['Args'] =
      {
        p_company_id: membership.company_id,
        p_stock_take_id: scopedStockTakeId,
        p_warehouse_id: warehouseId,
      };
    if (appliedMinimumVariance !== '')
      varianceArgs.p_minimum_absolute_variance_units = Number(
        appliedMinimumVariance,
      );
    const [progressResult, varianceResult, tasksResult, flagsResult] =
      await Promise.all([
        supabase.rpc('get_manager_progress', {
          p_company_id: membership.company_id,
          p_stock_take_id: scopedStockTakeId,
          p_warehouse_id: warehouseId,
        }),
        supabase.rpc('get_variances', varianceArgs),
        supabase
          .from('recount_tasks')
          .select('*')
          .eq('stock_take_id', scopedStockTakeId)
          .order('created_at'),
        supabase
          .from('count_flags')
          .select('id,count_id,created_at')
          .eq('stock_take_id', scopedStockTakeId)
          .eq('status', 'OPEN')
          .order('created_at'),
      ]);
    const requestError =
      progressResult.error ??
      varianceResult.error ??
      tasksResult.error ??
      flagsResult.error;
    if (requestError) {
      setError(requestError.message);
      setLoading(false);
      return;
    }
    const progressData = progressResult.data as unknown as ManagerProgress;
    const varianceData = varianceResult.data as unknown as VarianceResponse;
    if (!progressData.success || !varianceData.success) {
      setError('The management dashboard could not be loaded for this scope.');
    } else {
      setProgress(progressData);
      setVariances(varianceData.variances);
      setTasks(tasksResult.data ?? []);
      setFlags(flagsResult.data ?? []);
    }
    setLoading(false);
  }, [
    appliedMinimumVariance,
    membership.company_id,
    scopedStockTakeId,
    warehouseId,
  ]);

  const loadSettingsAndPeople = useCallback(async () => {
    if (!warehouseId) return;
    const allocationResult = await supabase
      .from('warehouse_memberships')
      .select('user_id')
      .eq('company_id', membership.company_id)
      .eq('warehouse_id', warehouseId)
      .eq('role', 'stock_taker')
      .eq('status', 'active');
    if (allocationResult.error) {
      setError(allocationResult.error.message);
      return;
    }
    const userIds = allocationResult.data?.map((row) => row.user_id) ?? [];
    setStockTakers(
      userIds.map((userId) => ({
        name: `Stock taker · ${userId.slice(0, 8)}`,
        userId,
      })),
    );

    if (!canChangeThresholds) return;
    const [companySettingsResult, warehouseSettingsResult, productSettings] =
      await Promise.all([
        supabase
          .from('company_settings')
          .select('default_variance_threshold_units')
          .eq('company_id', membership.company_id)
          .maybeSingle(),
        supabase
          .from('warehouse_settings')
          .select('variance_threshold_units,variance_threshold_active')
          .eq('warehouse_id', warehouseId)
          .maybeSingle(),
        supabase
          .from('product_warehouse_settings')
          .select(
            'product_id,variance_threshold_units,variance_threshold_active',
          )
          .eq('company_id', membership.company_id)
          .eq('warehouse_id', warehouseId),
      ]);
    const settingsError =
      companySettingsResult.error ??
      warehouseSettingsResult.error ??
      productSettings.error;
    if (settingsError) {
      setError(settingsError.message);
      return;
    }
    if (companySettingsResult.data)
      setCompanyThreshold(
        String(companySettingsResult.data.default_variance_threshold_units),
      );
    if (warehouseSettingsResult.data) {
      setWarehouseThreshold(
        String(warehouseSettingsResult.data.variance_threshold_units),
      );
      setWarehouseThresholdActive(
        warehouseSettingsResult.data.variance_threshold_active,
      );
    } else {
      setWarehouseThreshold('0');
      setWarehouseThresholdActive(false);
    }
    setProductThresholds(
      Object.fromEntries(
        (productSettings.data ?? []).map((setting) => [
          setting.product_id,
          {
            active: setting.variance_threshold_active,
            value: String(setting.variance_threshold_units),
          },
        ]),
      ),
    );
  }, [canChangeThresholds, membership.company_id, warehouseId]);

  useEffect(() => {
    queueMicrotask(() => void loadScope());
  }, [loadScope]);

  useEffect(() => {
    queueMicrotask(() => {
      void refreshDashboard();
      void loadSettingsAndPeople();
    });
  }, [loadSettingsAndPeople, refreshDashboard]);

  const productById = useMemo(
    () => new Map(variances.map((variance) => [variance.product_id, variance])),
    [variances],
  );

  async function runAction(
    action: () => PromiseLike<{
      data: unknown;
      error: { message: string } | null;
    }>,
    successMessage: string,
  ) {
    setBusy(true);
    setError('');
    setMessage('');
    const { data, error: actionError } = await action();
    const result = data as RpcResult | null;
    if (actionError) setError(actionError.message);
    else if (!result?.success)
      setError(asMessage(result ?? {}, 'The action could not be completed.'));
    else {
      setMessage(successMessage);
      await Promise.all([
        refreshDashboard(),
        loadScope(),
        loadSettingsAndPeople(),
      ]);
    }
    setBusy(false);
  }

  function wholeUnitValue(rawValue: string, label: string): number | undefined {
    if (!/^\d+$/.test(rawValue) || !Number.isSafeInteger(Number(rawValue))) {
      setError(`${label} must be a non-negative whole number.`);
      return undefined;
    }
    return Number(rawValue);
  }

  function applyVarianceFilter() {
    if (minimumVariance === '') {
      setAppliedMinimumVariance('');
      return;
    }
    const value = wholeUnitValue(minimumVariance, 'Minimum units');
    if (value !== undefined) setAppliedMinimumVariance(String(value));
  }

  async function saveCompanyThreshold() {
    const value = wholeUnitValue(companyThreshold, 'Company threshold');
    if (value === undefined) return;
    await runAction(
      () =>
        supabase.rpc('set_company_variance_threshold', {
          p_company_id: membership.company_id,
          p_threshold_units: value,
        }),
      'Company threshold saved.',
    );
  }

  async function saveWarehouseThreshold() {
    const value = wholeUnitValue(warehouseThreshold, 'Warehouse threshold');
    if (value === undefined) return;
    await runAction(
      () =>
        supabase.rpc('set_variance_threshold', {
          p_active: warehouseThresholdActive,
          p_company_id: membership.company_id,
          p_threshold_units: value,
          p_warehouse_id: warehouseId,
        }),
      'Warehouse threshold saved.',
    );
  }

  async function saveProductThreshold(productId: string) {
    const draft = productThresholds[productId];
    const value = wholeUnitValue(draft?.value ?? '', 'Product threshold');
    if (value === undefined) return;
    await runAction(
      () =>
        supabase.rpc('set_variance_threshold', {
          p_active: draft?.active ?? false,
          p_company_id: membership.company_id,
          p_product_id: productId,
          p_threshold_units: value,
          p_warehouse_id: warehouseId,
        }),
      'Product threshold saved.',
    );
  }

  async function createRecount(productId?: string) {
    const args: Database['public']['Functions']['create_recount_batch']['Args'] =
      {
        p_company_id: membership.company_id,
        p_stock_take_id: scopedStockTakeId,
        p_warehouse_id: warehouseId,
      };
    if (appliedMinimumVariance !== '')
      args.p_minimum_absolute_variance_units = Number(appliedMinimumVariance);
    if (productId) args.p_product_id = productId;
    await runAction(
      () => supabase.rpc('create_recount_batch', args),
      productId ? 'Product recount created.' : 'Recount batch created.',
    );
  }

  async function assignTasks() {
    if (selectedTasks.length === 0) {
      setError('Select at least one open recount task.');
      return;
    }
    const args: Database['public']['Functions']['assign_recount_tasks']['Args'] =
      {
        p_company_id: membership.company_id,
        p_recount_task_ids: selectedTasks,
        p_warehouse_id: warehouseId,
      };
    if (assigneeId) args.p_assigned_user_id = assigneeId;
    await runAction(
      () => supabase.rpc('assign_recount_tasks', args),
      assigneeId
        ? 'Recount tasks assigned.'
        : 'Recount tasks returned to pool.',
    );
    setSelectedTasks([]);
  }

  async function resolveFlag(flagId: string) {
    if (!resolutionNote.trim()) {
      setError('Enter a resolution note before resolving a flag.');
      return;
    }
    await runAction(
      () =>
        supabase.rpc('resolve_count_flag', {
          p_count_flag_id: flagId,
          p_resolution_note: resolutionNote,
        }),
      'Duplicate-count flag resolved.',
    );
    setResolutionNote('');
  }

  async function advanceLifecycle() {
    if (!selectedStockTake) return;
    if (selectedStockTake.status === 'REVIEW') {
      await runAction(
        () =>
          supabase.rpc('complete_stock_take', {
            p_company_id: membership.company_id,
            p_stock_take_id: scopedStockTakeId,
            p_warehouse_id: warehouseId,
          }),
        'Stock take completed.',
      );
    } else {
      await runAction(
        () =>
          supabase.rpc('move_stock_take_to_review', {
            p_company_id: membership.company_id,
            p_stock_take_id: scopedStockTakeId,
            p_warehouse_id: warehouseId,
          }),
        'Stock take moved to review.',
      );
    }
  }

  if (loading && warehouses.length === 0)
    return <main className="loading-shell">Loading management controls…</main>;

  const availableStockTakes = stockTakes.filter(
    (stockTake) => stockTake.warehouse_id === warehouseId,
  );

  return (
    <main className="manager-shell">
      <header className="manager-header">
        <div>
          <p className="eyebrow">{membership.role.replace('_', ' ')}</p>
          <h1>Stock control</h1>
          <p>{companyName}</p>
        </div>
        <button
          className="text-button"
          onClick={() => void supabase.auth.signOut()}
        >
          Sign out
        </button>
      </header>

      <section className="scope-bar" aria-label="Management scope">
        <label>
          Warehouse
          <select
            value={warehouseId}
            onChange={(event) => {
              const nextWarehouse = event.target.value;
              setWarehouseId(nextWarehouse);
              setSelectedTasks([]);
              setMessage('');
              setStockTakeId(
                stockTakes.find(
                  (stockTake) => stockTake.warehouse_id === nextWarehouse,
                )?.id ?? '',
              );
            }}
          >
            {warehouses.map((warehouse) => (
              <option key={warehouse.id} value={warehouse.id}>
                {warehouse.warehouse_code} · {warehouse.name}
              </option>
            ))}
          </select>
        </label>
        <label>
          Stock take
          <select
            value={scopedStockTakeId}
            onChange={(event) => {
              setStockTakeId(event.target.value);
              setSelectedTasks([]);
              setMessage('');
            }}
          >
            {availableStockTakes.map((stockTake) => (
              <option key={stockTake.id} value={stockTake.id}>
                {stockTake.status} · {stockTake.id.slice(0, 8)}
              </option>
            ))}
          </select>
        </label>
        <button
          className="secondary-button"
          disabled={loading}
          onClick={() => void refreshDashboard()}
        >
          Refresh
        </button>
      </section>

      {message && <div className="success-banner">{message}</div>}
      {error && <div className="error-banner">{error}</div>}
      {!selectedStockTake || !selectedWarehouse ? (
        <section className="manager-card empty-state">
          No active stock take is available in this management scope.
        </section>
      ) : (
        <>
          <section className="metric-grid" aria-label="Stock take progress">
            <article>
              <span>Progress</span>
              <strong>{progress?.progress_percent ?? 0}%</strong>
              <small>
                {progress?.covered_products ?? 0} of{' '}
                {progress?.snapshot_products ?? 0} products
              </small>
            </article>
            <article>
              <span>Count records</span>
              <strong>{progress?.initial_count_records ?? 0}</strong>
              <small>Immutable submissions</small>
            </article>
            <article>
              <span>Open recounts</span>
              <strong>{progress?.open_recounts ?? 0}</strong>
              <small>{progress?.completed_recounts ?? 0} completed</small>
            </article>
            <article>
              <span>Open flags</span>
              <strong>{progress?.open_duplicate_flags ?? 0}</strong>
              <small>Resolve before finalising</small>
            </article>
          </section>

          {canChangeThresholds ? (
            <section className="manager-card">
              <div className="section-heading">
                <div>
                  <p className="step-label">Variance policy</p>
                  <h2>Thresholds</h2>
                </div>
              </div>
              <div className="threshold-grid">
                <label>
                  Company fallback
                  <input
                    min="0"
                    inputMode="numeric"
                    type="number"
                    value={companyThreshold}
                    onChange={(event) =>
                      setCompanyThreshold(event.target.value)
                    }
                  />
                </label>
                <button
                  className="secondary-button"
                  disabled={busy}
                  onClick={() => void saveCompanyThreshold()}
                >
                  Save company
                </button>
                <label>
                  Warehouse units
                  <input
                    min="0"
                    inputMode="numeric"
                    type="number"
                    value={warehouseThreshold}
                    onChange={(event) =>
                      setWarehouseThreshold(event.target.value)
                    }
                  />
                </label>
                <label className="check-label">
                  <input
                    checked={warehouseThresholdActive}
                    onChange={(event) =>
                      setWarehouseThresholdActive(event.target.checked)
                    }
                    type="checkbox"
                  />
                  Active override
                </label>
                <button
                  className="secondary-button"
                  disabled={busy}
                  onClick={() => void saveWarehouseThreshold()}
                >
                  Save warehouse
                </button>
              </div>
            </section>
          ) : (
            <section className="manager-card compact-policy-card">
              <div>
                <p className="step-label">Variance policy</p>
                <h2>Admin controlled</h2>
              </div>
              <p className="muted-copy">
                Effective thresholds and their source are shown for every
                product below.
              </p>
            </section>
          )}

          <section className="manager-card">
            <div className="section-heading">
              <div>
                <p className="step-label">Derived control view</p>
                <h2>Variances</h2>
              </div>
              <div className="inline-actions">
                <label>
                  Minimum units
                  <input
                    min="0"
                    inputMode="numeric"
                    placeholder="All"
                    type="number"
                    value={minimumVariance}
                    onChange={(event) => setMinimumVariance(event.target.value)}
                  />
                </label>
                <button
                  className="secondary-button"
                  onClick={applyVarianceFilter}
                >
                  Apply
                </button>
                <button
                  className="primary-button"
                  disabled={busy}
                  onClick={() => void createRecount()}
                >
                  Generate required recounts
                </button>
              </div>
            </div>
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Product</th>
                    <th>SOH</th>
                    <th>Physical</th>
                    <th>Variance</th>
                    <th>Threshold</th>
                    <th>Control</th>
                  </tr>
                </thead>
                <tbody>
                  {variances.map((variance) => (
                    <tr key={variance.product_id}>
                      <td>
                        <strong>{variance.product_name}</strong>
                        <small>
                          {variance.product_code}
                          {variance.brand_name
                            ? ` · ${variance.brand_name}`
                            : ''}
                        </small>
                      </td>
                      <td>{variance.snapshot_units.toLocaleString()}</td>
                      <td>{variance.physical_units.toLocaleString()}</td>
                      <td
                        className={
                          variance.recount_required ? 'variance-alert' : ''
                        }
                      >
                        {variance.signed_variance_units > 0 ? '+' : ''}
                        {variance.signed_variance_units.toLocaleString()}
                      </td>
                      <td>
                        {variance.effective_threshold_units.toLocaleString()}{' '}
                        <small>{variance.threshold_source.toLowerCase()}</small>
                      </td>
                      <td>
                        {variance.recount_required &&
                        !variance.recount_status ? (
                          <button
                            className="table-action"
                            disabled={busy}
                            onClick={() =>
                              void createRecount(variance.product_id)
                            }
                          >
                            Recount
                          </button>
                        ) : (
                          <span className="status-chip">
                            {variance.recount_status ?? 'Within tolerance'}
                          </span>
                        )}
                        {canChangeThresholds && (
                          <div className="product-threshold">
                            <input
                              aria-label={`Threshold for ${variance.product_name}`}
                              min="0"
                              inputMode="numeric"
                              placeholder="Units"
                              type="number"
                              value={
                                productThresholds[variance.product_id]?.value ??
                                ''
                              }
                              onChange={(event) =>
                                setProductThresholds((current) => ({
                                  ...current,
                                  [variance.product_id]: {
                                    active:
                                      current[variance.product_id]?.active ??
                                      true,
                                    value: event.target.value,
                                  },
                                }))
                              }
                            />
                            <label className="check-label product-check">
                              <input
                                aria-label={`Use product override for ${variance.product_name}`}
                                checked={
                                  productThresholds[variance.product_id]
                                    ?.active ?? false
                                }
                                onChange={(event) =>
                                  setProductThresholds((current) => ({
                                    ...current,
                                    [variance.product_id]: {
                                      active: event.target.checked,
                                      value:
                                        current[variance.product_id]?.value ??
                                        '',
                                    },
                                  }))
                                }
                                type="checkbox"
                              />
                              Use
                            </label>
                            <button
                              className="table-action"
                              disabled={
                                busy ||
                                !productThresholds[variance.product_id]?.value
                              }
                              onClick={() =>
                                void saveProductThreshold(variance.product_id)
                              }
                            >
                              Set
                            </button>
                          </div>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>

          <section className="manager-grid">
            <article className="manager-card">
              <div className="section-heading">
                <div>
                  <p className="step-label">Dispatch</p>
                  <h2>Recount tasks</h2>
                </div>
                <span className="role-chip">
                  {tasks.filter((task) => task.status !== 'COMPLETED').length}{' '}
                  open
                </span>
              </div>
              <div className="task-list">
                {tasks.map((task) => (
                  <label className="task-row" key={task.id}>
                    <input
                      checked={selectedTasks.includes(task.id)}
                      disabled={
                        task.status === 'CLAIMED' || task.status === 'COMPLETED'
                      }
                      onChange={(event) =>
                        setSelectedTasks((current) =>
                          event.target.checked
                            ? [...current, task.id]
                            : current.filter((id) => id !== task.id),
                        )
                      }
                      type="checkbox"
                    />
                    <span>
                      <strong>
                        {productById.get(task.product_id)?.product_name ??
                          task.product_id.slice(0, 8)}
                      </strong>
                      <small>
                        {task.status} · {task.source_absolute_variance_units}{' '}
                        units
                      </small>
                    </span>
                  </label>
                ))}
              </div>
              <div className="assignment-bar">
                <select
                  aria-label="Recount assignee"
                  value={assigneeId}
                  onChange={(event) => setAssigneeId(event.target.value)}
                >
                  <option value="">Unassigned pool</option>
                  {stockTakers.map((stockTaker) => (
                    <option key={stockTaker.userId} value={stockTaker.userId}>
                      {stockTaker.name}
                    </option>
                  ))}
                </select>
                <button
                  className="secondary-button"
                  disabled={busy || selectedTasks.length === 0}
                  onClick={() => void assignTasks()}
                >
                  Apply assignment
                </button>
              </div>
            </article>

            <article className="manager-card">
              <div className="section-heading">
                <div>
                  <p className="step-label">Exceptions</p>
                  <h2>Duplicate flags</h2>
                </div>
                <span className="role-chip">{flags.length} open</span>
              </div>
              {flags.length === 0 ? (
                <p className="muted-copy">No open duplicate-count flags.</p>
              ) : (
                <>
                  <label>
                    Resolution note
                    <textarea
                      value={resolutionNote}
                      onChange={(event) =>
                        setResolutionNote(event.target.value)
                      }
                      placeholder="Record what was reviewed and decided."
                    />
                  </label>
                  <div className="task-list">
                    {flags.map((flag) => (
                      <div className="task-row" key={flag.id}>
                        <span>
                          <strong>Duplicate count</strong>
                          <small>
                            {new Date(flag.created_at).toLocaleString()} ·{' '}
                            {flag.count_id.slice(0, 8)}
                          </small>
                        </span>
                        <button
                          className="table-action"
                          disabled={busy}
                          onClick={() => void resolveFlag(flag.id)}
                        >
                          Resolve
                        </button>
                      </div>
                    ))}
                  </div>
                </>
              )}
            </article>
          </section>

          <section className="finalise-bar">
            <div>
              <strong>{selectedWarehouse.name}</strong>
              <span>Current state: {selectedStockTake.status}</span>
            </div>
            <button
              className="primary-button"
              disabled={
                busy ||
                !['ACTIVE', 'RECOUNT', 'REVIEW'].includes(
                  selectedStockTake.status,
                )
              }
              onClick={() => void advanceLifecycle()}
            >
              {selectedStockTake.status === 'REVIEW'
                ? 'Complete stock take'
                : 'Move to review'}
            </button>
          </section>
        </>
      )}
    </main>
  );
}
