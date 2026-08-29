import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {chmod, copyFile, mkdir, readFile, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import test from 'node:test';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const cli = path.join(root, 'bin', 'grex-js');

function run(args, options = {}) {
  return spawnSync(process.execPath, [options.cli ?? cli, ...args], {
    cwd: options.cwd ?? root,
    encoding: Object.hasOwn(options, 'encoding') ? options.encoding : 'utf8',
    input: options.input,
    env: {...process.env, ...options.env},
    timeout: options.timeout ?? 15_000,
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

test('help and version are stable', () => {
  const help = run(['--help']);
  assert.equal(help.status, 0);
  assert.equal(help.stderr, '');
  assert.match(help.stdout, /^Usage:\n  grex-js/);
  assert.match(help.stdout, /--digits/);
  assert.match(help.stdout, /--no-anchors/);
  assertSuccess(['--version'], 'grex-js 1.0.2');
});

test('default inference preserves exact documented results', () => {
  assertSuccess(['hello', 'world'], '^(?:hello|world)$');
  assertSuccess(['a', 'aa', 'aaa'], '^a(?:aa?)?$');
  assertSuccess([''], '^$');
  assertSuccess(['a.b', 'a*b'], '^a[*.]b$');
});

test('upstream sorting and duplicate collapse are visible', () => {
  const forward = run(['zebra', 'apple', 'mango']);
  const reverse = run(['mango', 'apple', 'zebra', 'apple']);
  assert.equal(forward.status, 0);
  assert.equal(reverse.status, 0);
  assert.equal(reverse.stdout, forward.stdout);
});

test('file and stdin records preserve delimiters, empties, controls, and Unicode', async () => {
  const work = path.join(tmpdir(), `grex-input-${process.pid}-${Date.now()}`);
  await mkdir(work, {recursive: true});
  const file = path.join(work, 'cases');
  await writeFile(file, Buffer.from('hello\r\nworld\n', 'utf8'));
  const positional = run(['hello', 'world']);
  assert.equal(run(['--input', file]).stdout, positional.stdout);
  assert.equal(run(['--input', '-'], {input: 'hello\nworld\n'}).stdout, positional.stdout);
  assert.equal(run([], {input: 'hello\nworld\n'}).stdout, positional.stdout);

  assertSuccess(['--input', '-'], '^$', {input: '\n'});
  const interior = run(['--input', '-'], {input: 'a\n\na\n'});
  assert.equal(interior.status, 0, interior.stderr);
  assert.doesNotMatch(interior.stdout, /undefined/);

  const literalCr = run(['--input', '-'], {input: 'a\r'});
  assert.equal(literalCr.status, 0);
  assert.ok(literalCr.stdout.includes(String.raw`\r`));

  const unicode = 'é\n💩\n';
  const unicodeResult = run(['--input', '-'], {input: unicode});
  assert.equal(unicodeResult.status, 0, unicodeResult.stderr);
  assert.equal(unicodeResult.stderr, '');

  const nul = run(['--input', '-'], {input: Buffer.from([0x61, 0x00, 0x62, 0x0a]), encoding: null});
  assert.equal(nul.status, 0);
  assert.deepEqual(nul.stdout, Buffer.from([0x5e, 0x61, 0x00, 0x62, 0x24, 0x0a]));
});

test('default-compatible output matches all supplied positive examples', () => {
  const examples = ['cat', 'car', 'cart', 'a+b', 'a.b'];
  const result = run(examples);
  assert.equal(result.status, 0, result.stderr);
  const source = result.stdout.slice(0, -1);
  const regex = new RegExp(source);
  for (const example of examples) assert.match(example, regex);
  for (const negative of ['ca', 'cars', 'ab']) assert.doesNotMatch(negative, regex);
});

test('all six character generalizers map to their upstream methods', () => {
  for (const [option, sample, expected] of [
    ['digits', '5', String.raw`^\d$`],
    ['non-digits', 'a', String.raw`^\D$`],
    ['whitespace', ' ', String.raw`^\s$`],
    ['non-whitespace', 'a', String.raw`^\S$`],
    ['words', 'a', String.raw`^\w$`],
    ['non-words', '!', String.raw`^\W$`],
  ]) {
    assertSuccess([`--${option}`, sample], expected);
  }
  assertSuccess(['--digits', '--words', 'a', 'aa', '123'],
    String.raw`^(?:\d\d\d|\w(?:\w)?)$`);
});

test('repetition conversion and thresholds preserve exact upstream output', () => {
  assertSuccess([
    '--repetitions', '--min-substring-length', '2', 'aa', 'bcbc', 'defdefdef',
  ], '^(?:aa|(?:bc){2}|(?:def){3})$');
  const defaults = run(['--repetitions', 'aaaa']);
  assert.equal(defaults.status, 0, defaults.stderr);
  assert.match(defaults.stdout, /\{4\}|\+|\*/);
});

test('rendering, case, capture, Unicode, verbose, and anchor settings map directly', () => {
  assertSuccess(['--ignore-case', 'abc'], '(?i)^abc$');
  assertSuccess(['--capture-groups', 'hello', 'world'], '^(hello|world)$');
  assertSuccess(['--escape-non-ascii', 'code-point', '💩'], String.raw`^\u{1f4a9}$`);
  assertSuccess(['--escape-non-ascii', 'surrogate-pair', 'You smell like 💩.'],
    String.raw`^You smell like \u{d83d}\u{dca9}\.$`);

  const verbose = run(['--verbose', 'hello', 'world']);
  assert.equal(verbose.status, 0);
  assert.equal(verbose.stderr, '');
  assert.match(verbose.stdout, /^\(\?x\)\n\^\n/);
  assert.ok(verbose.stdout.endsWith('$\n'));

  assertSuccess(['--no-start-anchor', 'hello'], 'hello$');
  assertSuccess(['--no-end-anchor', 'hello'], '^hello');
  assertSuccess(['--no-anchors', 'hello'], 'hello');
  const individual = run(['--no-start-anchor', '--no-end-anchor', 'hello']);
  const combined = run(['--no-anchors', 'hello']);
  assert.equal(individual.stdout, combined.stdout);
});

test('invalid option combinations and values are usage errors', () => {
  for (const args of [
    ['--bogus', 'a'],
    ['--digits', '--digits', 'a'],
    ['--input', 'a', '--input', 'b'],
    ['--input', 'file', 'a'],
    ['--escape-non-ascii', 'utf16', 'a'],
    ['--min-repetitions', '1', 'aa'],
    ['--min-substring-length', '1', 'aa'],
    ['--repetitions', '--min-repetitions', '0', 'aa'],
    ['--repetitions', '--min-repetitions', '-1', 'aa'],
    ['--repetitions', '--min-repetitions', '1.5', 'aa'],
    ['--repetitions', '--min-repetitions', '4294967296', 'aa'],
    ['--no-anchors', '--no-start-anchor', 'a'],
    ['--help', 'a'],
    ['--version', 'a'],
  ]) {
    const result = run(args);
    assert.equal(result.status, 2, `${args.join(' ')}: ${result.stderr}`);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /^grex-js:/);
    assert.doesNotMatch(result.stderr, /\n\s+at |node_modules/);
  }
});

test('empty lists, file failures, and invalid UTF-8 are runtime errors', async () => {
  const work = path.join(tmpdir(), `grex-errors-${process.pid}-${Date.now()}`);
  await mkdir(work, {recursive: true});
  const empty = path.join(work, 'empty');
  const invalid = path.join(work, 'invalid');
  await writeFile(empty, '');
  await writeFile(invalid, Buffer.from([0xff]));

  for (const invocation of [
    {args: [], input: ''},
    {args: ['--input', empty]},
    {args: ['--input', path.join(work, 'missing')]},
    {args: ['--input', invalid]},
  ]) {
    const result = run(invocation.args, {input: invocation.input});
    assert.equal(result.status, 1);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /^grex-js:/);
    assert.doesNotMatch(result.stderr, /\n\s+at |node_modules|undefined/);
  }
  const zero = run([], {input: ''});
  assert.equal(zero.stderr,
    'grex-js: No test cases have been provided for regular expression generation\n');
});

test('dependency and WASM resolution are executable-relative', async () => {
  const outside = path.join(tmpdir(), `grex-outside-${process.pid}-${Date.now()}`);
  await mkdir(outside, {recursive: true});
  assertSuccess(['hello', 'world'], '^(?:hello|world)$', {cwd: outside});

  const clean = path.join(tmpdir(), `grex-clean-${process.pid}-${Date.now()}`);
  await mkdir(path.join(clean, 'bin'), {recursive: true});
  await mkdir(path.join(clean, 'lib'), {recursive: true});
  await copyFile(cli, path.join(clean, 'bin', 'grex-js'));
  await copyFile(path.join(root, 'lib', 'node-cli.js'), path.join(clean, 'lib', 'node-cli.js'));
  await writeFile(path.join(clean, 'package.json'), '{"type":"module"}\n');
  await chmod(path.join(clean, 'bin', 'grex-js'), 0o755);
  const cleanCli = path.join(clean, 'bin', 'grex-js');
  assert.equal(run(['--help'], {cli: cleanCli}).status, 0);
  const missing = run(['--version'], {cli: cleanCli});
  assert.deepEqual(
    {status: missing.status, stdout: missing.stdout, stderr: missing.stderr},
    {
      status: 1,
      stdout: '',
      stderr: 'grex-js: @pemistahl/grex 1.0.2 is not installed; run npm ci\n',
    },
  );
});

test('controlled package records method order, build count, and final free', async () => {
  const fake = path.join(tmpdir(), `grex-fake-${process.pid}-${Date.now()}`);
  await mkdir(path.join(fake, 'bin'), {recursive: true});
  await mkdir(path.join(fake, 'lib'), {recursive: true});
  await mkdir(path.join(fake, 'node_modules', '@pemistahl', 'grex', 'node'), {recursive: true});
  await copyFile(cli, path.join(fake, 'bin', 'grex-js'));
  await copyFile(path.join(root, 'lib', 'node-cli.js'), path.join(fake, 'lib', 'node-cli.js'));
  await writeFile(path.join(fake, 'package.json'), '{"type":"module"}\n');
  await writeFile(path.join(fake, 'node_modules', '@pemistahl', 'grex', 'package.json'),
    JSON.stringify({name: '@pemistahl/grex', version: '1.0.2', main: 'node/grex.js'}));
  await writeFile(path.join(fake, 'node_modules', '@pemistahl', 'grex', 'node', 'grex.js'), `
const fs = require('node:fs');
function log(value) { fs.appendFileSync(process.env.GREX_CALLS, value + '\\n'); }
class RegExpBuilder {
  static from(values) { log('from:' + JSON.stringify(values)); return new RegExpBuilder(); }
  free() { log('free'); }
  build() { log('build'); return 'fake-pattern'; }
}
for (const name of [
  'withConversionOfDigits','withConversionOfNonDigits','withConversionOfWhitespace',
  'withConversionOfNonWhitespace','withConversionOfWords','withConversionOfNonWords',
  'withConversionOfRepetitions','withMinimumRepetitions','withMinimumSubstringLength',
  'withCaseInsensitiveMatching','withCapturingGroups','withEscapingOfNonAsciiChars',
  'withVerboseMode','withoutStartAnchor','withoutEndAnchor','withoutAnchors',
]) RegExpBuilder.prototype[name] = function(value) { log(name + ':' + String(value)); return this; };
module.exports = {RegExpBuilder};
`);
  const fakeCli = path.join(fake, 'bin', 'grex-js');
  await chmod(fakeCli, 0o755);
  const calls = path.join(fake, 'calls');
  const result = run([
    '--digits', '--non-digits', '--whitespace', '--non-whitespace', '--words', '--non-words',
    '--repetitions', '--min-repetitions', '2', '--min-substring-length', '3',
    '--ignore-case', '--capture-groups', '--escape-non-ascii', 'code-point', '--verbose',
    '--no-start-anchor', '--no-end-anchor', 'zebra', 'apple',
  ], {cli: fakeCli, env: {GREX_CALLS: calls}});
  assert.deepEqual(
    {status: result.status, stdout: result.stdout, stderr: result.stderr},
    {status: 0, stdout: 'fake-pattern\n', stderr: ''},
  );
  const log = (await readFile(calls, 'utf8')).trimEnd().split('\n');
  assert.deepEqual(log, [
    'from:["zebra","apple"]',
    'withConversionOfDigits:undefined',
    'withConversionOfNonDigits:undefined',
    'withConversionOfWhitespace:undefined',
    'withConversionOfNonWhitespace:undefined',
    'withConversionOfWords:undefined',
    'withConversionOfNonWords:undefined',
    'withConversionOfRepetitions:undefined',
    'withMinimumRepetitions:2',
    'withMinimumSubstringLength:3',
    'withCaseInsensitiveMatching:undefined',
    'withCapturingGroups:undefined',
    'withEscapingOfNonAsciiChars:false',
    'withVerboseMode:undefined',
    'withoutStartAnchor:undefined',
    'withoutEndAnchor:undefined',
    'build',
    'free',
  ]);
});

test('regex- and code-shaped samples remain inert literal data', () => {
  const samples = [
    '(?{code})', 'a|b', '$1', 'require("node:fs")', '`touch sentinel`', '[a-z]+',
  ];
  const result = run(samples);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stderr, '');
  assert.doesNotMatch(result.stdout, /\n\s+at /);
});
