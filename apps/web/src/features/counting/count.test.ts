import { describe, expect, it } from 'vitest';
import {
  calculateTotalUnits,
  CountValidationError,
  parseQuantityInput,
} from './count';

const packaging = {
  cases_per_layer: 10,
  cases_per_pallet: 60,
  units_per_case: 12,
};

describe('calculateTotalUnits', () => {
  it('calculates pallets, layers, cases and units canonically', () => {
    expect(
      calculateTotalUnits(packaging, {
        pallets: 1,
        layers: 2,
        cases: 3,
        units: 4,
      }),
    ).toBe(1000);
  });

  it('accepts an explicit zero physical count', () => {
    expect(
      calculateTotalUnits(
        {
          cases_per_layer: null,
          cases_per_pallet: null,
          units_per_case: null,
        },
        { pallets: 0, layers: 0, cases: 0, units: 0 },
      ),
    ).toBe(0);
  });

  it.each([
    ['pallets', { pallets: 1, layers: 0, cases: 0, units: 0 }],
    ['layers', { pallets: 0, layers: 1, cases: 0, units: 0 }],
    ['cases', { pallets: 0, layers: 0, cases: 1, units: 0 }],
  ] as const)('blocks %s when packaging is missing', (field, quantities) => {
    expect(() =>
      calculateTotalUnits(
        {
          cases_per_layer: null,
          cases_per_pallet: null,
          units_per_case: null,
        },
        quantities,
      ),
    ).toThrowError(CountValidationError);
    try {
      calculateTotalUnits(
        {
          cases_per_layer: null,
          cases_per_pallet: null,
          units_per_case: null,
        },
        quantities,
      );
    } catch (error) {
      expect((error as CountValidationError).field).toBe(field);
    }
  });

  it('rejects negative and fractional quantities', () => {
    expect(() =>
      calculateTotalUnits(packaging, {
        pallets: -1,
        layers: 0,
        cases: 0,
        units: 0,
      }),
    ).toThrow(/non-negative whole number/);
    expect(() =>
      calculateTotalUnits(packaging, {
        pallets: 0,
        layers: 0,
        cases: 0,
        units: 1.5,
      }),
    ).toThrow(/non-negative whole number/);
  });
});

describe('parseQuantityInput', () => {
  it('treats a blank field as zero and accepts digits', () => {
    expect(parseQuantityInput('')).toBe(0);
    expect(parseQuantityInput(' 12 ')).toBe(12);
  });

  it('rejects decimals and signs', () => {
    expect(() => parseQuantityInput('1.5')).toThrow();
    expect(() => parseQuantityInput('-1')).toThrow();
  });
});
