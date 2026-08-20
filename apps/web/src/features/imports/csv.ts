export interface ParsedCsv {
  headers: string[];
  rows: Record<string, string>[];
}

export function parseCsv(source: string): ParsedCsv {
  const cells: string[][] = [];
  let row: string[] = [];
  let value = '';
  let quoted = false;

  const text = source.replace(/^\uFEFF/, '');
  for (let index = 0; index < text.length; index += 1) {
    const character = text[index];
    if (quoted) {
      if (character === '"' && text[index + 1] === '"') {
        value += '"';
        index += 1;
      } else if (character === '"') quoted = false;
      else value += character;
      continue;
    }
    if (character === '"') quoted = true;
    else if (character === ',') {
      row.push(value.trim());
      value = '';
    } else if (character === '\n') {
      row.push(value.trim());
      if (row.some((cell) => cell !== '')) cells.push(row);
      row = [];
      value = '';
    } else if (character !== '\r') value += character;
  }
  if (quoted)
    throw new Error('The CSV file contains an unclosed quoted value.');
  row.push(value.trim());
  if (row.some((cell) => cell !== '')) cells.push(row);

  const headers = cells.shift() ?? [];
  if (headers.length === 0 || headers.some((header) => header === '')) {
    throw new Error('Every CSV column must have a heading.');
  }
  const normalized = new Set(headers.map((header) => header.toLowerCase()));
  if (normalized.size !== headers.length) {
    throw new Error('CSV column headings must be unique.');
  }

  return {
    headers,
    rows: cells.map((cellsInRow) => {
      if (cellsInRow.length > headers.length)
        throw new Error('A CSV row contains more values than the heading row.');
      return Object.fromEntries(
        headers.map((header, index) => [header, cellsInRow[index] ?? '']),
      );
    }),
  };
}

export function csvText(
  headers: string[],
  rows: ReadonlyArray<ReadonlyArray<string | number>>,
): string {
  const escape = (value: string | number) => {
    const textValue = String(value);
    return /[",\r\n]/.test(textValue)
      ? `"${textValue.replaceAll('"', '""')}"`
      : textValue;
  };
  return [headers, ...rows]
    .map((line) => line.map(escape).join(','))
    .join('\r\n');
}
