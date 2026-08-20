import { parseTable, type ParsedCsv } from './csv';

async function spreadsheetLibrary() {
  return import('@e965/xlsx');
}

export async function parseExcel(source: ArrayBuffer): Promise<ParsedCsv> {
  const XLSX = await spreadsheetLibrary();
  const workbook = XLSX.read(source, { type: 'array' });
  const sheetName = workbook.SheetNames[0];
  if (!sheetName) throw new Error('The Excel file does not contain a sheet.');
  const worksheet = workbook.Sheets[sheetName];
  if (!worksheet)
    throw new Error('The Excel file does not contain a readable sheet.');
  const cells = XLSX.utils.sheet_to_json<string[]>(worksheet, {
    blankrows: false,
    defval: '',
    header: 1,
    raw: false,
  });

  return parseTable(cells, 'Excel');
}

export async function excelTemplate(headers: string[]): Promise<Blob> {
  const XLSX = await spreadsheetLibrary();
  const workbook = XLSX.utils.book_new();
  const worksheet = XLSX.utils.aoa_to_sheet([headers]);
  worksheet['!autofilter'] = {
    ref: XLSX.utils.encode_range({
      s: { c: 0, r: 0 },
      e: { c: headers.length - 1, r: 0 },
    }),
  };
  worksheet['!cols'] = headers.map((header) => ({
    wch: Math.max(header.length + 4, 18),
  }));
  XLSX.utils.book_append_sheet(workbook, worksheet, 'Stock items');
  const output = XLSX.write(workbook, { bookType: 'xlsx', type: 'array' });
  return new Blob([output], {
    type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  });
}
