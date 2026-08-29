import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {chmod, copyFile, mkdir, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import test from 'node:test';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const cli = path.join(root, 'bin', 'oniguruma-parser');

function run(args, options = {}) {
  return spawnSync(process.execPath, [options.cli ?? cli, ...args], {
    cwd: options.cwd ?? root,
    encoding: options.encoding ?? 'utf8',
    input: options.input,
    env: {...process.env, ...options.env},
    timeout: options.timeout ?? 10_000,
  });
}

function successJson(args, options = {}) {
  const result = run(args, options);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stderr, '');
  assert.ok(result.stdout.endsWith('\n'));
  return JSON.parse(result.stdout);
}

test('top-level and subcommand help plus version are stable', () => {
  const help = run(['--help']);
  assert.equal(help.status, 0);
  assert.equal(help.stderr, '');
  assert.match(help.stdout, /oniguruma-parser parse/);
  assert.match(help.stdout, /oniguruma-parser optimize/);

  for (const command of ['parse', 'roundtrip', 'traverse', 'optimize']) {
    const commandHelp = run([command, '--help']);
    assert.equal(commandHelp.status, 0);
    assert.equal(commandHelp.stderr, '');
    assert.match(commandHelp.stdout, new RegExp(`^Usage: oniguruma-parser ${command}`));
    if (command === 'optimize') {
      assert.match(commandHelp.stdout, /--disable-optimization/);
    } else {
      assert.doesNotMatch(commandHelp.stdout, /--disable-optimization/);
    }
  }

  const version = run(['--version']);
  assert.deepEqual(
    {status: version.status, stdout: version.stdout, stderr: version.stderr},
    {status: 0, stdout: 'oniguruma-parser 0.12.2\n', stderr: ''},
  );
});

test('parse preserves Infinity and representative Oniguruma AST semantics', () => {
  const ast = successJson(['parse', 'a{1,}']);
  const quantifier = ast.body[0].body[0];
  assert.equal(ast.type, 'Regex');
  assert.equal(quantifier.type, 'Quantifier');
  assert.deepEqual(
    {min: quantifier.min, max: quantifier.max, value: quantifier.body.value},
    {min: 1, max: 'Infinity', value: 97},
  );
  assert.notEqual(quantifier.max, null);

  for (const pattern of [
    'é\\p{Letter}',
    '(?<word>a)\\g<word>',
    '(?<=a)b(?!c)',
    '[a-z&&[^aeiou]]',
    'a++',
    '(*FAIL)',
  ]) {
    const parsed = successJson(['parse', pattern]);
    assert.equal(parsed.type, 'Regex');
  }
});

test('pattern sources preserve complete UTF-8 data, NUL, whitespace, and emptiness', async () => {
  const work = path.join(tmpdir(), `onig-source-${process.pid}-${Date.now()}`);
  await mkdir(work, {recursive: true});
  const file = path.join(work, 'pattern');
  const pattern = ' aé\n';
  await writeFile(file, Buffer.from(pattern, 'utf8'));

  const positional = successJson(['roundtrip', pattern]);
  const fromFile = successJson(['roundtrip', '--input', file]);
  const explicitStdin = successJson(['roundtrip', '--input', '-'], {input: pattern});
  const implicitStdin = successJson(['roundtrip'], {input: pattern});
  assert.deepEqual(fromFile, positional);
  assert.deepEqual(explicitStdin, positional);
  assert.deepEqual(implicitStdin, positional);

  const nulPattern = 'a\0b';
  await writeFile(file, Buffer.from(nulPattern, 'utf8'));
  const nulFile = successJson(['roundtrip', '--input', file]);
  const nulStdin = successJson(['roundtrip', '--input', '-'], {input: nulPattern});
  assert.deepEqual(nulFile, nulStdin);
  assert.equal(nulFile.pattern, String.raw`a\x00b`);

  for (const invocation of [
    {args: ['parse', '']},
    {args: ['parse', '--input', '-'], input: ''},
    {args: ['parse'], input: ''},
  ]) {
    const empty = successJson(invocation.args, {input: invocation.input});
    assert.equal(empty.body[0].body.length, 0);
  }
});

test('roundtrip exposes generator canonicalization and flag handling', () => {
  assert.deepEqual(successJson(['roundtrip', 'a{1,}']), {pattern: 'a+', flags: ''});
  assert.deepEqual(successJson(['roundtrip', '--flags', 'iim', 'a']),
    {pattern: 'a', flags: 'im'});
  assert.deepEqual(successJson(['roundtrip', '--flags', 'y{g}', 'é']),
    {pattern: 'é', flags: 'y{g}'});
});

test('traverse counts every node without changing the AST', () => {
  assert.deepEqual(successJson(['traverse', '^.*']), {
    total: 6,
    byType: {
      Alternative: 1,
      Assertion: 1,
      CharacterSet: 1,
      Flags: 1,
      Quantifier: 1,
      Regex: 1,
    },
  });
  const nested = successJson(['traverse', '(?<name>a|é)\\k<name>']);
  assert.ok(nested.byType.CapturingGroup >= 1);
  assert.ok(nested.byType.Backreference >= 1);
  assert.ok(nested.byType.Character >= 2);
});

test('compile-time rules map directly to upstream parsing', () => {
  const capture = successJson([
    'parse', '--capture-group', '(a)(?<b>b)\\1',
  ]);
  assert.equal(capture.body[0].body[0].type, 'CapturingGroup');

  const singleline = successJson(['parse', '--singleline', '^$']);
  assert.deepEqual(
    singleline.body[0].body.map((node) => node.kind),
    ['string_start', 'string_end_newline'],
  );
});

test('optimizer maps optional transforms and orphan-backreference rules', () => {
  assert.deepEqual(successJson(['optimize', 'a|b']), {pattern: '[ab]', flags: ''});
  assert.deepEqual(
    successJson(['optimize', '--disable-optimization', 'alternationToClass', 'a|b']),
    {pattern: 'a|b', flags: ''},
  );
  assert.deepEqual(
    successJson([
      'optimize',
      '--disable-optimization', 'alternationToClass',
      '--disable-optimization', 'optionalize',
      'a|b',
    ]),
    {pattern: 'a|b', flags: ''},
  );
  assert.deepEqual(
    successJson(['optimize', '--allow-orphan-backrefs', String.raw`\1`]),
    {pattern: String.raw`\1`, flags: ''},
  );
});

test('invalid command lines are usage errors with no partial stdout', () => {
  for (const args of [
    [],
    ['unknown'],
    ['parse', '--bogus', 'a'],
    ['parse', 'a', 'b'],
    ['parse', '--input', 'file', 'a'],
    ['parse', '--input', 'a', '--input', 'b'],
    ['parse', '--disable-optimization', 'optionalize', 'a'],
    ['optimize', '--disable-optimization', 'not-a-transform', 'a'],
    ['optimize', '--disable-optimization', 'optionalize',
      '--disable-optimization', 'optionalize', 'a'],
    ['--version', 'extra'],
    ['parse', '--help', 'extra'],
  ]) {
    const result = run(args);
    assert.equal(result.status, 2, `${args.join(' ')}: ${result.stderr}`);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /^oniguruma-parser:/);
    assert.doesNotMatch(result.stderr, /\n\s+at /);
  }
});

test('upstream syntax, flag, and capture failures are normalized', () => {
  for (const args of [
    ['parse', '--flags', 'g', 'a'],
    ['parse', '('],
    ['parse', '(?(1)a|b)'],
    ['parse', '(?{javascript})'],
    ['parse', '(a)(?<b>b)\\1'],
    ['optimize', String.raw`\1`],
  ]) {
    const result = run(args);
    assert.equal(result.status, 1, `${args.join(' ')} should fail`);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /^oniguruma-parser:/);
    assert.doesNotMatch(result.stderr, /\n\s+at |node_modules/);
  }
});

test('file and decoding failures use runtime status', async () => {
  const work = path.join(tmpdir(), `onig-errors-${process.pid}-${Date.now()}`);
  await mkdir(work, {recursive: true});
  const bad = path.join(work, 'bad');
  await writeFile(bad, Buffer.from([0xff]));
  for (const args of [
    ['parse', '--input', path.join(work, 'missing')],
    ['parse', '--input', bad],
  ]) {
    const result = run(args);
    assert.equal(result.status, 1);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /^oniguruma-parser:/);
  }
});

test('dependency resolution is executable-relative and help is bootstrap-free', async () => {
  const outside = path.join(tmpdir(), `onig-outside-${process.pid}-${Date.now()}`);
  await mkdir(outside, {recursive: true});
  assert.deepEqual(successJson(['roundtrip', 'a{1,}'], {cwd: outside}),
    {pattern: 'a+', flags: ''});

  const clean = path.join(tmpdir(), `onig-clean-${process.pid}-${Date.now()}`);
  await mkdir(path.join(clean, 'bin'), {recursive: true});
  await mkdir(path.join(clean, 'lib'), {recursive: true});
  await copyFile(cli, path.join(clean, 'bin', 'oniguruma-parser'));
  await copyFile(path.join(root, 'lib', 'node-cli.js'), path.join(clean, 'lib', 'node-cli.js'));
  await writeFile(path.join(clean, 'package.json'), '{"type":"module"}\n');
  await chmod(path.join(clean, 'bin', 'oniguruma-parser'), 0o755);
  const cleanCli = path.join(clean, 'bin', 'oniguruma-parser');
  assert.equal(run(['--help'], {cli: cleanCli}).status, 0);
  const missing = run(['--version'], {cli: cleanCli});
  assert.deepEqual(
    {status: missing.status, stdout: missing.stdout, stderr: missing.stderr},
    {
      status: 1,
      stdout: '',
      stderr: 'oniguruma-parser: oniguruma-parser 0.12.2 is not installed; run npm ci\n',
    },
  );
});

test('pattern-shaped JavaScript remains inert data', async () => {
  const work = path.join(tmpdir(), `onig-safe-${process.pid}-${Date.now()}`);
  await mkdir(work, {recursive: true});
  const sentinel = path.join(work, 'sentinel');
  const pattern = `(?<code>require('node:fs').writeFileSync('${sentinel}','x'))`;
  const result = run(['traverse', pattern]);
  assert.equal(result.status, 0, result.stderr);
  const probe = spawnSync(process.execPath, ['-e',
    `process.exit(require('node:fs').existsSync(${JSON.stringify(sentinel)}) ? 1 : 0)`]);
  assert.equal(probe.status, 0);
});
