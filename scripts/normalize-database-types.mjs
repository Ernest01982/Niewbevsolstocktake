import { readFile, writeFile } from 'node:fs/promises';
import { URL } from 'node:url';

const databaseTypesUrl = new URL(
  '../apps/web/src/types/database.types.ts',
  import.meta.url,
);
const generatedTypes = await readFile(databaseTypesUrl, 'utf8');

await writeFile(databaseTypesUrl, generatedTypes.trimEnd() + '\n', 'utf8');
