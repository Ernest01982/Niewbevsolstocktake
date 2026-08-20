import { describe, expect, it } from 'vitest';
import { csvText, parseCsv } from './csv';

describe('CSV helpers', () => {
  it('parses quoted commas, escaped quotes, and blank cells', () => {
    expect(parseCsv('Code,Name,Brand\r\nA-1,"Wine, Red","Say ""Hi"""')).toEqual(
      {
        headers: ['Code', 'Name', 'Brand'],
        rows: [{ Code: 'A-1', Name: 'Wine, Red', Brand: 'Say "Hi"' }],
      },
    );
  });

  it('rejects duplicate headings', () => {
    expect(() => parseCsv('Code,code\nA-1,A-2')).toThrow(
      'headings must be unique',
    );
  });

  it('rejects an unclosed quote', () => {
    expect(() => parseCsv('Code,Name\nA-1,"Broken')).toThrow('unclosed');
  });

  it('writes a safe CSV that can be parsed again', () => {
    const source = csvText(['ItemCode', 'Quantity'], [['A,"1', 12]]);
    expect(parseCsv(source).rows[0]).toEqual({
      ItemCode: 'A,"1',
      Quantity: '12',
    });
  });
});
