import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {chmod, copyFile, mkdir, readFile, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {fileURLToPath, pathToFileURL} from 'node:url';
import path from 'node:path';
import test from 'node:test';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const cli = path.join(root, 'bin', 'regex-trie-js');

function run(args, options = {}) {
  return spawnSync(process.execPath, [options.cli ?? cli, ...args], {
    cwd: options.cwd ?? root,
    encoding: Object.hasOwn(options, 'encoding') ? options.encoding : 'utf8',
    input: options.input,
    env: {...process.env, ...options.env},
    timeout: options.timeout ?? 10_000,
  });
}

function assertSuccess(args, expected, options = {}) {
  const result = run(args, options);
  assert.deepEqual(
    {status: result.status, stdout: result.stdout, stderr: result.stderr},
    {status: 0, stdout: `${expected}\n`, stderr: ''},
  );
  return result;
}

function parseJsonLines(stdout) {
  assert.ok(stdout.endsWith('\n'));
  return stdout.slice(0, -1).split('\n').map((line) => JSON.parse(line));
}

test('top-level and subcommand help plus version are stable', () => {
  const help = run(['--help']);
  assert.equal(help.status, 0);
  assert.equal(help.stderr, '');
  assert.match(help.stdout, /regex-trie-js build/);
  assert.match(help.stdout, /regex-trie-js contains/);
  assert.match(help.stdout, /regex-trie-js match/);

  for (const command of ['build', 'contains', 'match']) {
    const commandHelp = run([command, '--help']);
    assert.equal(commandHelp.status, 0);
    assert.equal(commandHelp.stderr, '');
    assert.match(commandHelp.stdout, new RegExp(`^Usage: regex-trie-js ${command}`));
    if (command === 'build') {
      assert.doesNotMatch(commandHelp.stdout, /--candidate/);
    } else {
      assert.match(commandHelp.stdout, /--candidate/);
    }
  }
  assertSuccess(['--version'], 'regex-trie-js 1.0.4');
});

test('build preserves exact upstream source examples', () => {
  assertSuccess(['build', 'foo', 'bar', 'baz'], '(?:foo|ba[rz])');
  assertSuccess(['build', 'f', 'fo', 'fox'], 'f(?:ox?)?');
  assertSuccess(['build', 'foo', 'food', 'foods'], 'foo(?:ds?)?');
  assertSuccess(['build', 'a+b', 'a.b', 'a*b'], String.raw`a(?:\+b|\.b|\*b)`);
  assertSuccess(['build', 'café', '💩', '漢字'],
    String.raw`(?:caf\xE9|\uD83D\uDCA9|\u6F22\u5B57)`);
});

test('source order is observable without wrapper sorting', () => {
  assertSuccess(['build', 'a', 'b'], '[ab]');
  assertSuccess(['build', 'b', 'a'], '[ba]');
  assertSuccess(['build', '9', '1'], '[19]');
});

test('phrase sources preserve LF, CRLF, empties, whitespace, controls, and NUL', async () => {
  const work = path.join(tmpdir(), `trie-phrases-${process.pid}-${Date.now()}`);
  await mkdir(work, {recursive: true});
  const first = path.join(work, 'phrases');
  await writeFile(first, Buffer.from('foo\r\nbar\nbaz\n', 'utf8'));
  const positional = run(['build', 'foo', 'bar', 'baz']);
  assert.equal(run(['build', '--input', first]).stdout, positional.stdout);
  assert.equal(run(['build', '--input', '-'], {input: 'foo\nbar\nbaz\n'}).stdout,
    positional.stdout);
  assert.equal(run(['build'], {input: 'foo\nbar\nbaz\n'}).stdout, positional.stdout);

  assertSuccess(['build', '--input', '-'], 'foo', {input: 'foo\n\n'});
  assertSuccess(['build', '--input', '-'], String.raw`foo\\r`, {input: 'foo\r'});
  assertSuccess(['build', '--input', '-'], 'foo', {input: 'foo\nfoo\n\n'});

  const nul = run(['build', '--input', '-'], {
    input: Buffer.from([0x61, 0x00, 0x62, 0x0a]),
    encoding: null,
  });
  assert.equal(nul.status, 0);
  assert.deepEqual(nul.stdout, Buffer.from('a\\0b\n'));
});

test('empty and duplicate phrases retain upstream distinctions', () => {
  assertSuccess(['build', '', 'foo', 'foo', ''], 'foo');
  const contains = run(['contains', '--candidate=', '--candidate', 'foo', '', 'foo', 'foo']);
  assert.equal(contains.status, 0, contains.stderr);
  assert.deepEqual(parseJsonLines(contains.stdout), [
    {candidate: '', contains: false},
    {candidate: 'foo', contains: true},
  ]);

  const emptyTrie = run(['contains', '--candidate', 'foo'], {input: ''});
  assert.equal(emptyTrie.status, 0, emptyTrie.stderr);
  assert.deepEqual(parseJsonLines(emptyTrie.stdout), [{candidate: 'foo', contains: false}]);

  for (const command of ['build', 'match']) {
    const args = command === 'match' ? [command, '--candidate', 'foo', ''] : [command, ''];
    const result = run(args);
    assert.equal(result.status, 1);
    assert.equal(result.stdout, '');
    assert.equal(result.stderr, 'regex-trie-js: no non-empty phrases were added\n');
  }
});

test('contains reports exact membership and preserves candidate JSON Lines', async () => {
  const candidates = ['foo', 'food', 'afoo', 'FOO', 'bat', '', 'line\nbreak', '\0'];
  const argumentCandidates = candidates.slice(0, -1);
  const result = run([
    'contains', ...argumentCandidates.flatMap((value) => ['--candidate', value]),
    'foo', 'bar', 'baz',
  ]);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stderr, '');
  assert.deepEqual(parseJsonLines(result.stdout), argumentCandidates.map((candidate) => ({
    candidate,
    contains: candidate === 'foo',
  })));
  assert.doesNotMatch(result.stdout, /\nline\nbreak/);

  const work = path.join(tmpdir(), `trie-jsonl-${process.pid}-${Date.now()}`);
  await mkdir(work, {recursive: true});
  const input = path.join(work, 'candidates');
  await writeFile(input, Buffer.from([0x00, 0x0a]));
  const nul = run(['contains', '--candidate-input', input, 'foo']);
  assert.equal(nul.status, 0, nul.stderr);
  assert.deepEqual(parseJsonLines(nul.stdout), [{candidate: '\0', contains: false}]);
});

test('match exposes case-sensitive unanchored RegExp semantics', () => {
  const candidates = ['foo', 'food', 'afoo', 'FOO', 'bat', ''];
  const result = run([
    'match', ...candidates.flatMap((value) => ['--candidate', value]), 'foo', 'bar', 'baz',
  ]);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(parseJsonLines(result.stdout), [
    {candidate: 'foo', matches: true},
    {candidate: 'food', matches: true},
    {candidate: 'afoo', matches: true},
    {candidate: 'FOO', matches: false},
    {candidate: 'bat', matches: false},
    {candidate: '', matches: false},
  ]);
});

test('candidate files and stdin preserve records and reject zero records', async () => {
  const work = path.join(tmpdir(), `trie-candidates-${process.pid}-${Date.now()}`);
  await mkdir(work, {recursive: true});
  const candidates = path.join(work, 'candidates');
  await writeFile(candidates, Buffer.from('foo\r\nfood\n\n', 'utf8'));
  const fileResult = run(['contains', '--candidate-input', candidates, 'foo']);
  assert.deepEqual(parseJsonLines(fileResult.stdout), [
    {candidate: 'foo', contains: true},
    {candidate: 'food', contains: false},
    {candidate: '', contains: false},
  ]);
  const stdinResult = run(['match', '--candidate-input', '-', 'foo'], {
    input: 'foo\nfood\n',
  });
  assert.deepEqual(parseJsonLines(stdinResult.stdout), [
    {candidate: 'foo', matches: true},
    {candidate: 'food', matches: true},
  ]);

  await writeFile(candidates, '');
  const zero = run(['contains', '--candidate-input', candidates, 'foo']);
  assert.deepEqual(
    {status: zero.status, stdout: zero.stdout, stderr: zero.stderr},
    {status: 1, stdout: '', stderr: 'regex-trie-js: candidate input contains no records\n'},
  );
});

test('upstream backspace and NUL-octal defects remain characterized', async () => {
  const work = path.join(tmpdir(), `trie-controls-${process.pid}-${Date.now()}`);
  await mkdir(work, {recursive: true});
  const phrase = path.join(work, 'phrase');
  const candidate = path.join(work, 'candidate');

  await writeFile(phrase, Buffer.from([0x08, 0x0a]));
  await writeFile(candidate, Buffer.from([0x08, 0x0a]));
  assertSuccess(['build', '--input', phrase], String.raw`\b`);
  const backspaceMatch = run(['match', '--input', phrase, '--candidate-input', candidate]);
  assert.deepEqual(parseJsonLines(backspaceMatch.stdout), [{candidate: '\b', matches: false}]);

  await writeFile(phrase, Buffer.from([0x00, 0x31, 0x0a]));
  await writeFile(candidate, Buffer.from([0x00, 0x31, 0x0a]));
  assertSuccess(['build', '--input', phrase], String.raw`\01`);
  const nulMatch = run(['match', '--input', phrase, '--candidate-input', candidate]);
  assert.deepEqual(parseJsonLines(nulMatch.stdout), [{candidate: '\u00001', matches: false}]);
});

test('regex metacharacters remain literals and slash remains constructor source', () => {
  const phrases = ['^(foo|bar]', 'car[a-z]zoo', 'a/b', '(?{code})', '$1', 'a+b'];
  const build = run(['build', ...phrases]);
  assert.equal(build.status, 0, build.stderr);
  assert.equal(build.stderr, '');
  assert.ok(build.stdout.includes('/b'));
  const source = build.stdout.slice(0, -1);
  const regex = new RegExp(source);
  for (const phrase of phrases) assert.match(phrase, regex);
});

test('invalid command lines are usage errors', () => {
  for (const args of [
    [],
    ['unknown'],
    ['build', '--bogus', 'foo'],
    ['build', '--input', 'a', '--input', 'b'],
    ['build', '--input', 'file', 'foo'],
    ['build', '--candidate', 'foo', 'foo'],
    ['contains', 'foo'],
    ['contains', '--candidate', 'foo', '--candidate-input', 'file', 'foo'],
    ['contains', '--candidate-input', '-', '--input', '-'],
    ['--version', 'extra'],
    ['build', '--version'],
    ['build', '--help', 'foo'],
  ]) {
    const result = run(args);
    assert.equal(result.status, 2, `${args.join(' ')}: ${result.stderr}`);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /^regex-trie-js:/);
    assert.doesNotMatch(result.stderr, /\n\s+at |node_modules/);
  }
});

test('file, decoding, and recursion failures are normalized', async () => {
  const work = path.join(tmpdir(), `trie-errors-${process.pid}-${Date.now()}`);
  await mkdir(work, {recursive: true});
  const invalid = path.join(work, 'invalid');
  await writeFile(invalid, Buffer.from([0xff]));
  for (const args of [
    ['build', '--input', path.join(work, 'missing')],
    ['build', '--input', invalid],
    ['contains', '--candidate-input', invalid, 'foo'],
  ]) {
    const result = run(args);
    assert.equal(result.status, 1);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /^regex-trie-js:/);
    assert.doesNotMatch(result.stderr, /\n\s+at |node_modules/);
  }

  const deep = run(['build', 'x'.repeat(20_000)], {timeout: 5_000});
  assert.equal(deep.status, 1);
  assert.equal(deep.stdout, '');
  assert.match(deep.stderr, /^regex-trie-js:/);
  assert.doesNotMatch(deep.stderr, /\n\s+at |node_modules/);
});

test('dependency resolution is executable-relative and help is bootstrap-free', async () => {
  const outside = path.join(tmpdir(), `trie-outside-${process.pid}-${Date.now()}`);
  await mkdir(outside, {recursive: true});
  assertSuccess(['build', 'foo', 'bar', 'baz'], '(?:foo|ba[rz])', {cwd: outside});

  const clean = path.join(tmpdir(), `trie-clean-${process.pid}-${Date.now()}`);
  await mkdir(path.join(clean, 'bin'), {recursive: true});
  await mkdir(path.join(clean, 'lib'), {recursive: true});
  await copyFile(cli, path.join(clean, 'bin', 'regex-trie-js'));
  await copyFile(path.join(root, 'lib', 'node-cli.js'), path.join(clean, 'lib', 'node-cli.js'));
  await writeFile(path.join(clean, 'package.json'), '{"type":"module"}\n');
  await chmod(path.join(clean, 'bin', 'regex-trie-js'), 0o755);
  const cleanCli = path.join(clean, 'bin', 'regex-trie-js');
  assert.equal(run(['--help'], {cli: cleanCli}).status, 0);
  const missing = run(['--version'], {cli: cleanCli});
  assert.deepEqual(
    {status: missing.status, stdout: missing.stdout, stderr: missing.stderr},
    {
      status: 1,
      stdout: '',
      stderr: 'regex-trie-js: regex-trie 1.0.4 is not installed; run npm ci\n',
    },
  );
});

test('controlled package proves direct API call counts', async () => {
  const fake = path.join(tmpdir(), `trie-fake-${process.pid}-${Date.now()}`);
  await mkdir(path.join(fake, 'bin'), {recursive: true});
  await mkdir(path.join(fake, 'lib'), {recursive: true});
  await mkdir(path.join(fake, 'node_modules', 'regex-trie'), {recursive: true});
  await copyFile(cli, path.join(fake, 'bin', 'regex-trie-js'));
  await copyFile(path.join(root, 'lib', 'node-cli.js'), path.join(fake, 'lib', 'node-cli.js'));
  await writeFile(path.join(fake, 'package.json'), '{"type":"module"}\n');
  await writeFile(path.join(fake, 'node_modules', 'regex-trie', 'package.json'),
    JSON.stringify({name: 'regex-trie', version: '1.0.4', main: 'index.js'}));
  await writeFile(path.join(fake, 'node_modules', 'regex-trie', 'index.js'), `
const fs = require('node:fs');
function log(value) { fs.appendFileSync(process.env.TRIE_CALLS, value + '\\n'); }
class RegexTrie {
  add(values) { log('add:' + JSON.stringify(values)); return this; }
  contains(value) { log('contains:' + value); return value === 'yes'; }
  toString() { log('toString'); return 'fake'; }
  toRegExp() { log('toRegExp'); return {test(value) { log('test:' + value); return true; }}; }
}
module.exports = RegexTrie;
`);
  const fakeCli = path.join(fake, 'bin', 'regex-trie-js');
  await chmod(fakeCli, 0o755);

  const buildCalls = path.join(fake, 'build-calls');
  assertSuccess(['build', 'zebra', 'apple'], 'fake',
    {cli: fakeCli, env: {TRIE_CALLS: buildCalls}});
  assert.equal(await readFile(buildCalls, 'utf8'),
    'add:["zebra","apple"]\ntoString\n');

  const containsCalls = path.join(fake, 'contains-calls');
  const contains = run(['contains', '--candidate', 'yes', '--candidate', 'no', 'zebra'],
    {cli: fakeCli, env: {TRIE_CALLS: containsCalls}});
  assert.equal(contains.status, 0, contains.stderr);
  assert.equal(await readFile(containsCalls, 'utf8'),
    'add:["zebra"]\ncontains:yes\ncontains:no\n');

  const matchCalls = path.join(fake, 'match-calls');
  const match = run(['match', '--candidate', 'one', '--candidate', 'two', 'zebra'],
    {cli: fakeCli, env: {TRIE_CALLS: matchCalls}});
  assert.equal(match.status, 0, match.stderr);
  assert.equal(await readFile(matchCalls, 'utf8'),
    'add:["zebra"]\ntoRegExp\ntest:one\ntest:two\n');
});

test('stdout EPIPE is quiet while other write failures are normalized', async () => {
  const work = path.join(tmpdir(), `trie-stdout-${process.pid}-${Date.now()}`);
  await mkdir(work, {recursive: true});
  const harness = path.join(work, 'stdout.mjs');
  const helper = pathToFileURL(path.join(root, 'lib', 'node-cli.js')).href;
  await writeFile(harness, `
import {runCli, writeStdout} from ${JSON.stringify(helper)};
process.stdout.write = (_output, callback) => {
  const error = Object.assign(new Error('injected write failure'), {code: process.env.WRITE_CODE});
  queueMicrotask(() => callback(error));
  return false;
};
await runCli('regex-trie-js', async () => writeStdout('complete output\\n'));
`);

  const epipe = spawnSync(process.execPath, [harness], {
    encoding: 'utf8', env: {...process.env, WRITE_CODE: 'EPIPE'},
  });
  assert.deepEqual(
    {status: epipe.status, stdout: epipe.stdout, stderr: epipe.stderr},
    {status: 0, stdout: '', stderr: ''},
  );

  const eio = spawnSync(process.execPath, [harness], {
    encoding: 'utf8', env: {...process.env, WRITE_CODE: 'EIO'},
  });
  assert.deepEqual(
    {status: eio.status, stdout: eio.stdout, stderr: eio.stderr},
    {
      status: 1,
      stdout: '',
      stderr: 'regex-trie-js: cannot write stdout: injected write failure\n',
    },
  );
});
