import { describe, expect, it } from 'vitest';
import { excelTemplate, parseExcel } from './excel';

describe('Excel helpers', () => {
  it('creates a stock-item template that can be parsed again', async () => {
    const headers = ['product_code', 'name', 'brand'];
    const template = await excelTemplate(headers);

    await expect(parseExcel(await template.arrayBuffer())).resolves.toEqual({
      headers,
      rows: [],
    });
  });

  it('reads populated stock-item rows from the first sheet', async () => {
    const XLSX = await import('@e965/xlsx');
    const workbook = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(
      workbook,
      XLSX.utils.aoa_to_sheet([
        ['product_code', 'name', 'units_per_case'],
        ['000123', 'Red Wine', 12],
      ]),
      'Stock items',
    );
    const source = XLSX.write(workbook, {
      bookType: 'xlsx',
      type: 'array',
    });

    await expect(parseExcel(source)).resolves.toEqual({
      headers: ['product_code', 'name', 'units_per_case'],
      rows: [
        {
          name: 'Red Wine',
          product_code: '000123',
          units_per_case: '12',
        },
      ],
    });
  });
});
