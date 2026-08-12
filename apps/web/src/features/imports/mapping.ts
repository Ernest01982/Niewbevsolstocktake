export const productMasterLogicalFields = [
  'product_code',
  'name',
  'brand',
  'barcode',
  'units_per_case',
  'cases_per_layer',
  'cases_per_pallet',
] as const;

export const stockSnapshotLogicalFields = [
  'product_code',
  'quantity_on_hand',
] as const;

export type ProductMasterLogicalField =
  (typeof productMasterLogicalFields)[number];
export type StockSnapshotLogicalField =
  (typeof stockSnapshotLogicalFields)[number];
export type ImportKind = 'product_master' | 'stock_snapshot';

export type ImportColumnMapping = Record<string, string>;

export type MappingValidationResult =
  | { success: true; mapping: ImportColumnMapping }
  | {
      success: false;
      errors: Array<{
        code: 'duplicate_source_column' | 'missing_required_mapping';
        logicalField: string;
      }>;
    };

const requiredFields: Record<ImportKind, readonly string[]> = {
  product_master: ['product_code', 'name'],
  stock_snapshot: ['product_code', 'quantity_on_hand'],
};

const supportedFields: Record<ImportKind, readonly string[]> = {
  product_master: productMasterLogicalFields,
  stock_snapshot: stockSnapshotLogicalFields,
};

export function validateColumnMapping(
  kind: ImportKind,
  assignments: Readonly<Record<string, string | null | undefined>>,
): MappingValidationResult {
  const mapping: ImportColumnMapping = {};
  const errors: Extract<MappingValidationResult, { success: false }>['errors'] =
    [];
  const assignedSourceColumns = new Map<string, string>();

  for (const logicalField of supportedFields[kind]) {
    const sourceColumn = assignments[logicalField]?.trim();

    if (!sourceColumn) {
      if (requiredFields[kind].includes(logicalField)) {
        errors.push({
          code: 'missing_required_mapping',
          logicalField,
        });
      }
      continue;
    }

    const normalizedSourceColumn = sourceColumn.toLocaleLowerCase();
    const existingField = assignedSourceColumns.get(normalizedSourceColumn);

    if (existingField) {
      errors.push({
        code: 'duplicate_source_column',
        logicalField,
      });
      continue;
    }

    assignedSourceColumns.set(normalizedSourceColumn, logicalField);
    mapping[logicalField] = sourceColumn;
  }

  return errors.length > 0
    ? { success: false, errors }
    : { success: true, mapping };
}
