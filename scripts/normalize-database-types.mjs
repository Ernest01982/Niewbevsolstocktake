import { readFile, writeFile } from 'node:fs/promises';
import { URL } from 'node:url';

const databaseTypesUrl = new URL(
  '../apps/web/src/types/database.types.ts',
  import.meta.url,
);
const generatedTypes = await readFile(databaseTypesUrl, 'utf8');
const stableTypeLines = generatedTypes.replaceAll('\r\n', '\n').split('\n');
const internalMetadataStart = stableTypeLines.findIndex((line) =>
  line.includes('Allows to automatically instantiate createClient'),
);

if (internalMetadataStart >= 0) {
  const publicSchemaStart = stableTypeLines.findIndex(
    (line, index) => index > internalMetadataStart && line === '  public: {',
  );

  if (publicSchemaStart < 0) {
    throw new Error('Generated database types are missing the public schema.');
  }

  stableTypeLines.splice(
    internalMetadataStart,
    publicSchemaStart - internalMetadataStart,
  );
}

const stableTypes = stableTypeLines.join('\n');

await writeFile(databaseTypesUrl, stableTypes.trimEnd() + '\n', 'utf8');
