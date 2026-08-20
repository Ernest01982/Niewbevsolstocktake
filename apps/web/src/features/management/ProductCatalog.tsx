import { useCallback, useEffect, useMemo, useState } from 'react';
import { supabase } from '../../lib/supabase';
import type { Database, Json } from '../../types/database.types';
import {
  productMasterLogicalFields,
  validateColumnMapping,
} from '../imports/mapping';
import { csvText, parseCsv, type ParsedCsv } from '../imports/csv';

type Product = Database['public']['Tables']['products']['Row'];
type Brand = Database['public']['Tables']['brands']['Row'];
type ImportJob = Database['public']['Tables']['import_jobs']['Row'];
type ImportIssue = Database['public']['Tables']['import_issues']['Row'];

interface ProductDraft {
  barcode: string;
  brand: string;
  casesPerLayer: string;
  casesPerPallet: string;
  name: string;
  productCode: string;
  unitsPerCase: string;
}

interface ImportResponse {
  error?: { message?: string };
  import_job_id?: string;
  success?: boolean;
  totals?: {
    accepted: number;
    flagged: number;
    rejected: number;
    total: number;
  };
}

const emptyDraft: ProductDraft = {
  barcode: '',
  brand: '',
  casesPerLayer: '',
  casesPerPallet: '',
  name: '',
  productCode: '',
  unitsPerCase: '',
};

const fieldLabels: Record<(typeof productMasterLogicalFields)[number], string> =
  {
    barcode: 'Barcode',
    brand: 'Brand',
    cases_per_layer: 'Cases per layer',
    cases_per_pallet: 'Cases per pallet',
    name: 'Product name',
    product_code: 'Product code',
    units_per_case: 'Units per case',
  };

const fieldAliases: Record<
  (typeof productMasterLogicalFields)[number],
  string[]
> = {
  barcode: ['barcode', 'ean', 'ean13'],
  brand: ['brand', 'brand name'],
  cases_per_layer: ['cases_per_layer', 'cases per layer'],
  cases_per_pallet: ['cases_per_pallet', 'cases per pallet'],
  name: ['name', 'description', 'product name', 'item description'],
  product_code: ['product_code', 'product code', 'code', 'item code'],
  units_per_case: ['units_per_case', 'units per case', 'pack size'],
};

function positiveInteger(value: string): number | null {
  return value === '' ? null : Number(value);
}

async function sha256(source: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(source),
  );
  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, '0'),
  ).join('');
}

export function ProductCatalog({ companyId }: { companyId: string }) {
  const [products, setProducts] = useState<Product[]>([]);
  const [brands, setBrands] = useState<Brand[]>([]);
  const [jobs, setJobs] = useState<ImportJob[]>([]);
  const [issues, setIssues] = useState<ImportIssue[]>([]);
  const [draft, setDraft] = useState<ProductDraft>(emptyDraft);
  const [editingId, setEditingId] = useState<string>();
  const [search, setSearch] = useState('');
  const [showArchived, setShowArchived] = useState(false);
  const [parsed, setParsed] = useState<ParsedCsv>();
  const [sourceFile, setSourceFile] = useState<File>();
  const [sourceText, setSourceText] = useState('');
  const [mapping, setMapping] = useState<Record<string, string>>({});
  const [importSummary, setImportSummary] =
    useState<ImportResponse['totals']>();
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');

  const load = useCallback(async () => {
    const [productResult, brandResult, jobResult] = await Promise.all([
      supabase
        .from('products')
        .select('*')
        .eq('company_id', companyId)
        .order('product_code'),
      supabase
        .from('brands')
        .select('*')
        .eq('company_id', companyId)
        .order('name'),
      supabase
        .from('import_jobs')
        .select('*')
        .eq('company_id', companyId)
        .eq('kind', 'product_master')
        .order('started_at', { ascending: false })
        .limit(10),
    ]);
    const loadError =
      productResult.error ?? brandResult.error ?? jobResult.error;
    if (loadError) setError(loadError.message);
    else {
      setProducts(productResult.data ?? []);
      setBrands(brandResult.data ?? []);
      setJobs(jobResult.data ?? []);
    }
  }, [companyId]);

  useEffect(() => {
    queueMicrotask(() => void load());
  }, [load]);

  const brandById = useMemo(
    () => new Map(brands.map((brand) => [brand.id, brand.name])),
    [brands],
  );
  const visibleProducts = products.filter((product) => {
    const query = search.trim().toLowerCase();
    return (
      (showArchived || product.status === 'active') &&
      (!query ||
        product.product_code.toLowerCase().includes(query) ||
        product.name.toLowerCase().includes(query) ||
        (product.barcode ?? '').toLowerCase().includes(query) ||
        (brandById.get(product.brand_id ?? '') ?? '')
          .toLowerCase()
          .includes(query))
    );
  });

  function edit(product?: Product) {
    setEditingId(product?.id);
    setDraft(
      product
        ? {
            barcode: product.barcode ?? '',
            brand: brandById.get(product.brand_id ?? '') ?? '',
            casesPerLayer: String(product.cases_per_layer ?? ''),
            casesPerPallet: String(product.cases_per_pallet ?? ''),
            name: product.name,
            productCode: product.product_code,
            unitsPerCase: String(product.units_per_case ?? ''),
          }
        : emptyDraft,
    );
    setError('');
    setMessage('');
  }

  async function saveProduct(status: 'active' | 'inactive' = 'active') {
    if (!draft.productCode.trim() || !draft.name.trim()) {
      setError('Product code and product name are required.');
      return;
    }
    for (const [label, value] of [
      ['Units per case', draft.unitsPerCase],
      ['Cases per layer', draft.casesPerLayer],
      ['Cases per pallet', draft.casesPerPallet],
    ] as const) {
      if (value !== '' && (!/^\d+$/.test(value) || Number(value) < 1)) {
        setError(`${label} must be a positive whole number or blank.`);
        return;
      }
    }
    setBusy(true);
    setError('');
    setMessage('');
    const saveArgs: Database['public']['Functions']['save_product']['Args'] = {
      p_company_id: companyId,
      p_name: draft.name,
      p_product_code: draft.productCode,
      p_status: status,
    };
    if (draft.barcode) saveArgs.p_barcode = draft.barcode;
    if (draft.brand) saveArgs.p_brand_name = draft.brand;
    const casesPerLayer = positiveInteger(draft.casesPerLayer);
    const casesPerPallet = positiveInteger(draft.casesPerPallet);
    const unitsPerCase = positiveInteger(draft.unitsPerCase);
    if (casesPerLayer !== null) saveArgs.p_cases_per_layer = casesPerLayer;
    if (casesPerPallet !== null) saveArgs.p_cases_per_pallet = casesPerPallet;
    if (unitsPerCase !== null) saveArgs.p_units_per_case = unitsPerCase;
    if (editingId) saveArgs.p_product_id = editingId;
    const { data, error: saveError } = await supabase.rpc(
      'save_product',
      saveArgs,
    );
    const result = data as ImportResponse | null;
    if (saveError) setError(saveError.message);
    else if (!result?.success)
      setError(result?.error?.message ?? 'The stock item could not be saved.');
    else {
      setMessage(
        status === 'inactive' ? 'Stock item archived.' : 'Stock item saved.',
      );
      edit();
      await load();
    }
    setBusy(false);
  }

  async function selectFile(file?: File) {
    setError('');
    setMessage('');
    setIssues([]);
    setImportSummary(undefined);
    setParsed(undefined);
    setSourceFile(file);
    if (!file) return;
    if (!file.name.toLowerCase().endsWith('.csv')) {
      setError(
        'Please save the spreadsheet as a CSV file before uploading it.',
      );
      return;
    }
    try {
      const text = await file.text();
      const nextParsed = parseCsv(text);
      if (nextParsed.rows.length === 0)
        throw new Error('The CSV file has headings but no stock-item rows.');
      setSourceText(text);
      setParsed(nextParsed);
      setMapping(
        Object.fromEntries(
          productMasterLogicalFields.map((field) => [
            field,
            nextParsed.headers.find((header) =>
              fieldAliases[field].includes(header.trim().toLowerCase()),
            ) ?? '',
          ]),
        ),
      );
    } catch (caught) {
      setError(
        caught instanceof Error
          ? caught.message
          : 'The CSV file could not be read.',
      );
    }
  }

  function downloadTemplate() {
    const template = csvText([...productMasterLogicalFields], []);
    const blobUrl = URL.createObjectURL(
      new Blob([`\uFEFF${template}`], { type: 'text/csv;charset=utf-8' }),
    );
    const link = document.createElement('a');
    link.href = blobUrl;
    link.download = 'stock-item-upload-template.csv';
    link.click();
    URL.revokeObjectURL(blobUrl);
    setError('');
    setMessage(
      'CSV template downloaded. Product code and product name are required.',
    );
  }

  async function runImport() {
    if (!parsed || !sourceFile) return;
    const validation = validateColumnMapping('product_master', mapping);
    if (!validation.success) {
      setError(
        'Map Product code and Product name, and do not reuse the same CSV column.',
      );
      return;
    }
    setBusy(true);
    setError('');
    setMessage('');
    const { data, error: importError } = await supabase.rpc(
      'import_product_master',
      {
        p_column_mapping: validation.mapping as Json,
        p_company_id: companyId,
        p_rows: parsed.rows as Json,
        p_source_filename: sourceFile.name,
        p_source_metadata: { uploaded_from: 'admin_product_catalog' },
        p_source_sha256: await sha256(sourceText),
      },
    );
    const result = data as ImportResponse | null;
    if (importError) setError(importError.message);
    else if (!result?.success)
      setError(
        result?.error?.message ?? 'The product file could not be imported.',
      );
    else {
      setImportSummary(result.totals);
      setMessage('Bulk stock-item upload completed.');
      if (result.import_job_id) {
        const issueResult = await supabase
          .from('import_issues')
          .select('*')
          .eq('import_job_id', result.import_job_id)
          .order('row_number');
        if (issueResult.error) setError(issueResult.error.message);
        else setIssues(issueResult.data ?? []);
      }
      await load();
    }
    setBusy(false);
  }

  return (
    <section className="catalog-stack" aria-label="Stock item catalogue">
      <div className="section-heading">
        <div>
          <p className="step-label">Admin catalogue</p>
          <h2>Stock items</h2>
        </div>
        <span className="role-chip">
          {products.filter((product) => product.status === 'active').length}{' '}
          active
        </span>
      </div>
      {message && <div className="success-banner">{message}</div>}
      {error && <div className="error-banner">{error}</div>}

      <div className="catalog-grid">
        <article className="sub-card">
          <div className="section-heading compact-heading">
            <h3>{editingId ? 'Edit stock item' : 'Add stock item'}</h3>
            {editingId && (
              <button className="text-button" onClick={() => edit()}>
                Cancel
              </button>
            )}
          </div>
          <div className="form-grid">
            <label>
              Product code
              <input
                value={draft.productCode}
                onChange={(event) =>
                  setDraft({ ...draft, productCode: event.target.value })
                }
              />
            </label>
            <label>
              Product name
              <input
                value={draft.name}
                onChange={(event) =>
                  setDraft({ ...draft, name: event.target.value })
                }
              />
            </label>
            <label>
              Brand
              <input
                list="brand-options"
                value={draft.brand}
                onChange={(event) =>
                  setDraft({ ...draft, brand: event.target.value })
                }
              />
            </label>
            <datalist id="brand-options">
              {brands.map((brand) => (
                <option key={brand.id} value={brand.name} />
              ))}
            </datalist>
            <label>
              Barcode
              <input
                value={draft.barcode}
                onChange={(event) =>
                  setDraft({ ...draft, barcode: event.target.value })
                }
              />
            </label>
            <label>
              Units per case
              <input
                min="1"
                inputMode="numeric"
                type="number"
                value={draft.unitsPerCase}
                onChange={(event) =>
                  setDraft({ ...draft, unitsPerCase: event.target.value })
                }
              />
            </label>
            <label>
              Cases per layer
              <input
                min="1"
                inputMode="numeric"
                type="number"
                value={draft.casesPerLayer}
                onChange={(event) =>
                  setDraft({ ...draft, casesPerLayer: event.target.value })
                }
              />
            </label>
            <label>
              Cases per pallet
              <input
                min="1"
                inputMode="numeric"
                type="number"
                value={draft.casesPerPallet}
                onChange={(event) =>
                  setDraft({ ...draft, casesPerPallet: event.target.value })
                }
              />
            </label>
          </div>
          <div className="inline-button-row">
            <button
              className="primary-button"
              disabled={busy}
              onClick={() => void saveProduct()}
            >
              Save stock item
            </button>
            {editingId && (
              <button
                className="danger-button"
                disabled={busy}
                onClick={() => void saveProduct('inactive')}
              >
                Archive
              </button>
            )}
          </div>
        </article>

        <article className="sub-card">
          <p className="step-label">CSV spreadsheet</p>
          <h3>Bulk upload</h3>
          <p className="muted-copy">
            Download the correctly aligned template, populate it, then upload
            the completed CSV. Product code and product name are required.
          </p>
          <button
            className="secondary-button template-button"
            onClick={downloadTemplate}
            type="button"
          >
            Download CSV template
          </button>
          <input
            aria-label="Choose stock item CSV"
            accept=".csv,text/csv"
            type="file"
            onChange={(event) => void selectFile(event.target.files?.[0])}
          />
          {parsed && (
            <>
              <div className="mapping-grid">
                {productMasterLogicalFields.map((field) => (
                  <label key={field}>
                    {fieldLabels[field]}
                    {['product_code', 'name'].includes(field) ? ' *' : ''}
                    <select
                      value={mapping[field] ?? ''}
                      onChange={(event) =>
                        setMapping({ ...mapping, [field]: event.target.value })
                      }
                    >
                      <option value="">Not included</option>
                      {parsed.headers.map((header) => (
                        <option key={header} value={header}>
                          {header}
                        </option>
                      ))}
                    </select>
                  </label>
                ))}
              </div>
              <p className="muted-copy">
                {parsed.rows.length.toLocaleString()} rows ready · previewing
                the first 5
              </p>
              <div className="table-wrap compact-table">
                <table>
                  <thead>
                    <tr>
                      {parsed.headers.map((header) => (
                        <th key={header}>{header}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {parsed.rows.slice(0, 5).map((row, index) => (
                      <tr key={index}>
                        {parsed.headers.map((header) => (
                          <td key={header}>{row[header]}</td>
                        ))}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <button
                className="primary-button"
                disabled={busy}
                onClick={() => void runImport()}
              >
                Import {parsed.rows.length.toLocaleString()} stock items
              </button>
            </>
          )}
          {importSummary && (
            <div className="import-summary">
              <strong>{importSummary.accepted} accepted</strong>
              <span>{importSummary.flagged} flagged</span>
              <span>{importSummary.rejected} rejected</span>
            </div>
          )}
          {issues.length > 0 && (
            <div className="issue-list">
              <strong>Rows needing attention</strong>
              {issues.map((issue) => (
                <span key={issue.id}>
                  Row {issue.row_number}: {issue.message}
                </span>
              ))}
            </div>
          )}
        </article>
      </div>

      <article className="sub-card">
        <div className="section-heading compact-heading">
          <div>
            <h3>Product catalogue</h3>
            <p className="muted-copy">
              Edit, search, archive, and restore stock items.
            </p>
          </div>
          <div className="catalog-filters">
            <input
              aria-label="Search stock items"
              placeholder="Search code, name, brand or barcode"
              value={search}
              onChange={(event) => setSearch(event.target.value)}
            />
            <label className="check-label">
              <input
                checked={showArchived}
                type="checkbox"
                onChange={(event) => setShowArchived(event.target.checked)}
              />
              Show archived
            </label>
          </div>
        </div>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Code</th>
                <th>Stock item</th>
                <th>Barcode</th>
                <th>Packaging</th>
                <th>Status</th>
                <th>Action</th>
              </tr>
            </thead>
            <tbody>
              {visibleProducts.map((product) => (
                <tr key={product.id}>
                  <td>{product.product_code}</td>
                  <td>
                    <strong>{product.name}</strong>
                    <small>
                      {brandById.get(product.brand_id ?? '') ?? 'No brand'}
                    </small>
                  </td>
                  <td>{product.barcode ?? '—'}</td>
                  <td>
                    {product.units_per_case ?? '—'} /{' '}
                    {product.cases_per_layer ?? '—'} /{' '}
                    {product.cases_per_pallet ?? '—'}
                  </td>
                  <td>
                    <span className="status-chip">
                      {product.status === 'inactive'
                        ? 'archived'
                        : product.status}
                    </span>
                  </td>
                  <td>
                    <button
                      className="table-action"
                      onClick={() => edit(product)}
                    >
                      Edit
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {visibleProducts.length === 0 && (
          <p className="empty-state">No matching stock items.</p>
        )}
      </article>

      <article className="sub-card">
        <h3>Recent product uploads</h3>
        {jobs.length === 0 ? (
          <p className="muted-copy">No bulk uploads yet.</p>
        ) : (
          <div className="task-list">
            {jobs.map((job) => (
              <div className="task-row" key={job.id}>
                <span>
                  <strong>{job.source_filename}</strong>
                  <small>
                    {new Date(job.started_at).toLocaleString()} ·{' '}
                    {job.total_rows} rows
                  </small>
                </span>
                <span className="status-chip">
                  {job.status.replaceAll('_', ' ')}
                </span>
              </div>
            ))}
          </div>
        )}
      </article>
    </section>
  );
}
