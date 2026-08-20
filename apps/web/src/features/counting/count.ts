export type CountType = 'BULK' | 'PICK_FACE';

export interface PackagingMaster {
  cases_per_layer: number | null;
  cases_per_pallet: number | null;
  units_per_case: number | null;
}

export interface CountQuantities {
  cases: number;
  layers: number;
  pallets: number;
  units: number;
}

export interface CachedProduct extends PackagingMaster {
  barcode: string | null;
  company_id: string;
  id: string;
  name: string;
  product_code: string;
  updated_at: string;
}

export class CountValidationError extends Error {
  constructor(
    message: string,
    readonly field?: keyof CountQuantities,
  ) {
    super(message);
    this.name = 'CountValidationError';
  }
}

function assertQuantity(value: number, field: keyof CountQuantities) {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new CountValidationError(
      `${field[0]!.toUpperCase()}${field.slice(1)} must be a non-negative whole number.`,
      field,
    );
  }
}

export function calculateTotalUnits(
  packaging: PackagingMaster,
  quantities: CountQuantities,
): number {
  for (const field of ['pallets', 'layers', 'cases', 'units'] as const) {
    assertQuantity(quantities[field], field);
  }

  if (
    quantities.pallets > 0 &&
    (packaging.cases_per_pallet === null || packaging.units_per_case === null)
  ) {
    throw new CountValidationError(
      'Add cases per pallet and units per case before counting pallets.',
      'pallets',
    );
  }
  if (
    quantities.layers > 0 &&
    (packaging.cases_per_layer === null || packaging.units_per_case === null)
  ) {
    throw new CountValidationError(
      'Add cases per layer and units per case before counting layers.',
      'layers',
    );
  }
  if (quantities.cases > 0 && packaging.units_per_case === null) {
    throw new CountValidationError(
      'Add units per case before counting cases.',
      'cases',
    );
  }

  const total =
    quantities.pallets *
      (packaging.cases_per_pallet ?? 0) *
      (packaging.units_per_case ?? 0) +
    quantities.layers *
      (packaging.cases_per_layer ?? 0) *
      (packaging.units_per_case ?? 0) +
    quantities.cases * (packaging.units_per_case ?? 0) +
    quantities.units;

  if (!Number.isSafeInteger(total)) {
    throw new CountValidationError('The calculated unit total is too large.');
  }
  return total;
}

export function parseQuantityInput(rawValue: string): number {
  const value = rawValue.trim();
  if (value === '') return 0;
  if (!/^\d+$/.test(value)) {
    throw new CountValidationError(
      'Quantities must be non-negative whole numbers.',
    );
  }
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed)) {
    throw new CountValidationError('The entered quantity is too large.');
  }
  return parsed;
}
