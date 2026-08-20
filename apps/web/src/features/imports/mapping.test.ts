import { describe, expect, it } from 'vitest';
import { validateColumnMapping } from './mapping';

describe('validateColumnMapping', () => {
  it('accepts arbitrary source headings for the canonical product fields', () => {
    expect(
      validateColumnMapping('product_master', {
        product_code: ' Customer Item ',
        name: 'Long Description',
        brand: 'Brand Heading',
        barcode: '',
        units_per_case: 'Units Case',
      }),
    ).toEqual({
      success: true,
      mapping: {
        product_code: 'Customer Item',
        name: 'Long Description',
        brand: 'Brand Heading',
        units_per_case: 'Units Case',
      },
    });
  });

  it('requires only the canonical product identity fields', () => {
    expect(validateColumnMapping('product_master', {})).toEqual({
      success: false,
      errors: [
        { code: 'missing_required_mapping', logicalField: 'product_code' },
        { code: 'missing_required_mapping', logicalField: 'name' },
      ],
    });
  });

  it('requires product and quantity headings for an SOH snapshot', () => {
    expect(
      validateColumnMapping('stock_snapshot', {
        product_code: 'ERP Item',
      }),
    ).toEqual({
      success: false,
      errors: [
        {
          code: 'missing_required_mapping',
          logicalField: 'quantity_on_hand',
        },
      ],
    });
  });

  it('rejects assigning the same source heading twice', () => {
    expect(
      validateColumnMapping('stock_snapshot', {
        product_code: 'Item',
        quantity_on_hand: ' item ',
      }),
    ).toEqual({
      success: false,
      errors: [
        {
          code: 'duplicate_source_column',
          logicalField: 'quantity_on_hand',
        },
      ],
    });
  });

  it('ignores unsupported assignments instead of inventing logical fields', () => {
    expect(
      validateColumnMapping('stock_snapshot', {
        product_code: 'Item',
        quantity_on_hand: 'SOH',
        selling_price: 'Price',
      }),
    ).toEqual({
      success: true,
      mapping: {
        product_code: 'Item',
        quantity_on_hand: 'SOH',
      },
    });
  });
});
