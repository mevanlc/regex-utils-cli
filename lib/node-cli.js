import {readFile} from 'node:fs/promises';
import path from 'node:path';

export class CliError extends Error {
  constructor(status, message, usageHint = false) {
    super(message);
    this.status = status;
    this.usageHint = usageHint;
  }
}

export function usageError(message) {
  throw new CliError(2, message, true);
}

export function runtimeError(message) {
  throw new CliError(1, message);
}

export function errorMessage(error) {
  if (error instanceof Error && error.message) {
    return error.message;
  }
  if (typeof error === 'string' && error) {
    return error;
  }
  return 'unknown failure';
}

export function cleanMessage(message) {
  return String(message || 'unknown failure').replace(/\s*\n\s*/gu, ' ').trim();
}

export function optionCounts(tokens) {
  const counts = new Map();
  for (const token of tokens) {
    if (token.kind === 'option') {
      counts.set(token.name, (counts.get(token.name) ?? 0) + 1);
    }
  }
  return counts;
}

export function rejectRepeatedOptions(tokens, allowed = new Set()) {
  for (const [name, count] of optionCounts(tokens)) {
    if (count > 1 && !allowed.has(name)) {
      usageError(`--${name} may be supplied only once`);
    }
  }
}

export function decodeUtf8(bytes, source) {
  try {
    return new TextDecoder('utf-8', {fatal: true}).decode(bytes);
  } catch (error) {
    runtimeError(`${source} is not valid UTF-8: ${errorMessage(error)}`);
  }
}

export async function readInput(pathname, label) {
  try {
    let bytes;
    if (pathname === '-') {
      const chunks = [];
      for await (const chunk of process.stdin) {
        chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
      }
      bytes = Buffer.concat(chunks);
    } else {
      bytes = await readFile(pathname);
    }
    return decodeUtf8(bytes, label);
  } catch (error) {
    if (error instanceof CliError) {
      throw error;
    }
    runtimeError(`cannot read ${label}: ${errorMessage(error)}`);
  }
}

export function splitRecords(text) {
  if (text.length === 0) {
    return [];
  }
  const records = text.split('\n');
  const endsWithLf = text.endsWith('\n');
  if (endsWithLf) {
    records.pop();
  }
  const delimitedCount = endsWithLf ? records.length : Math.max(0, records.length - 1);
  for (let index = 0; index < delimitedCount; index += 1) {
    if (records[index].endsWith('\r')) {
      records[index] = records[index].slice(0, -1);
    }
  }
  return records;
}

export async function findPackageMetadata(entryPath, expectedName) {
  let directory = path.dirname(entryPath);
  while (true) {
    const candidate = path.join(directory, 'package.json');
    try {
      const metadata = JSON.parse(await readFile(candidate, 'utf8'));
      if (metadata.name === expectedName) {
        return metadata;
      }
    } catch (error) {
      if (error?.code !== 'ENOENT') {
        throw error;
      }
    }
    const parent = path.dirname(directory);
    if (parent === directory) {
      throw new Error(`cannot find package metadata for ${expectedName}`);
    }
    directory = parent;
  }
}

export async function writeStdout(output) {
  try {
    await new Promise((resolve, reject) => {
      const onError = (error) => {
        process.stdout.off('error', onError);
        reject(error);
      };
      process.stdout.once('error', onError);
      process.stdout.write(output, (error) => {
        process.stdout.off('error', onError);
        if (error) {
          reject(error);
        } else {
          resolve();
        }
      });
    });
  } catch (error) {
    if (error?.code === 'EPIPE') {
      return;
    }
    runtimeError(`cannot write stdout: ${errorMessage(error)}`);
  }
}

export async function runCli(program, main) {
  try {
    await main();
  } catch (error) {
    const status = error instanceof CliError ? error.status : 1;
    const usageHint = error instanceof CliError && error.usageHint;
    process.stderr.write(`${program}: ${cleanMessage(errorMessage(error))}\n`);
    if (usageHint) {
      process.stderr.write(`Try '${program} --help' for usage.\n`);
    }
    process.exitCode = status;
  }
}
