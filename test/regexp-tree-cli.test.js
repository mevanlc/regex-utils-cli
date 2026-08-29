import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import test from 'node:test';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const cli = path.join(root, 'node_modules', 'regexp-tree-cli', 'bin', 'regexp-tree-cli');

function run(args, options = {}) {
  return spawnSync(process.execPath, [cli, ...args], {
    cwd: options.cwd ?? root,
    encoding: 'utf8',
    input: options.input,
    env: {...process.env, FORCE_COLOR: '0', ...options.env},
    timeout: 10_000,
  });
}

test('native help and version remain unwrapped', () => {
  const help = run(['--help']);
  assert.equal(help.status, 0);
  assert.equal(help.stderr, '');
  assert.match(help.stdout, /^Usage: regexp-tree-cli/);
  assert.match(help.stdout, /--expression, -e/);
  assert.match(help.stdout, /--table, -t/);

  const version = run(['--version']);
  assert.deepEqual(
    {status: version.status, stdout: version.stdout, stderr: version.stderr},
    {status: 0, stdout: '0.0.21\n', stderr: ''},
  );
});

test('parse mode returns the structured ECMAScript AST', () => {
  const result = run(['-e', '/a|b/i']);
  assert.equal(result.status, 0);
  assert.equal(result.stderr, '');
  assert.ok(result.stdout.endsWith('\n'));
  const ast = JSON.parse(result.stdout);
  assert.equal(ast.type, 'RegExp');
  assert.equal(ast.body.type, 'Disjunction');
  assert.deepEqual(
    [ast.body.left.value, ast.body.left.codePoint, ast.body.right.value, ast.body.right.codePoint],
    ['a', 97, 'b', 98],
  );
  assert.equal(ast.flags, 'i');
});

test('empty and Unicode expressions preserve native AST semantics and locations', () => {
  const empty = run(['-e', '//']);
  assert.equal(empty.status, 0);
  assert.equal(JSON.parse(empty.stdout).body, null);

  const unicode = run(['-e', '/é/u', '--loc']);
  assert.equal(unicode.status, 0);
  assert.equal(unicode.stderr, '');
  const ast = JSON.parse(unicode.stdout);
  assert.equal(ast.body.value, 'é');
  assert.equal(ast.body.codePoint, 233);
  assert.equal(ast.flags, 'u');
  assert.deepEqual(ast.body.loc.start, {line: 1, column: 1, offset: 1});
  assert.deepEqual(ast.body.loc.end, {line: 1, column: 2, offset: 2});
});

test('representative syntax stays parser data', () => {
  for (const expression of [
    String.raw`/a\+b[cd]{2,3}(?=x)/`,
    String.raw`/(?<word>\w+)\k<word>/u`,
    String.raw`/\p{Script=Greek}+/u`,
    '/ a  # comment\n b /x',
  ]) {
    const result = run(['-e', expression]);
    assert.equal(result.status, 0, `${expression}: ${result.stderr}`);
    assert.equal(JSON.parse(result.stdout).type, 'RegExp');
  }
});

test('optimizer and compat preserve exact native formatting', () => {
  const optimized = run(['-e', String.raw`/[a-zA-Z_0-9][A-Z_\da-z]*e{1,}/`, '-o']);
  assert.deepEqual(
    {status: optimized.status, stdout: optimized.stdout, stderr: optimized.stderr},
    {status: 0, stdout: '\n Optimized: /\\w+e+/ \n\n', stderr: ''},
  );

  const compat = run(['-e', String.raw`/(?<all>.)\k<all>/s`, '-c']);
  assert.deepEqual(
    {status: compat.status, stdout: compat.stdout, stderr: compat.stderr},
    {status: 0, stdout: '\n Compat: /([\\0-\\uFFFF])\\1/ \n\n', stderr: ''},
  );
});

test('all automaton table modes exercise their native headings', () => {
  const nfa = run(['-e', '/a|b|c/', '--table', 'nfa']);
  assert.equal(nfa.status, 0);
  assert.match(nfa.stdout, /> - starting/);
  assert.match(nfa.stdout, /✓ - accepting/);
  assert.match(nfa.stdout, /NFA transition table:/);
  assert.doesNotMatch(nfa.stdout, /DFA:/);

  const dfa = run(['-e', '/a|b|c/', '--table', 'dfa']);
  assert.equal(dfa.status, 0);
  assert.match(dfa.stdout, /DFA: Original transition table:/);
  assert.match(dfa.stdout, /DFA: Minimized transition table:/);

  const all = run(['-e', '/a|b|c/', '--table', 'all']);
  assert.equal(all.status, 0);
  assert.match(all.stdout, /NFA transition table:/);
  assert.match(all.stdout, /DFA: Original transition table:/);
  assert.match(all.stdout, /DFA: Minimized transition table:/);
});

test('native expression replacement and operation precedence remain visible', () => {
  const repeated = run(['-e', '/a/', '-e', '/b/i']);
  assert.equal(repeated.status, 0);
  const ast = JSON.parse(repeated.stdout);
  assert.equal(ast.body.value, 'b');
  assert.equal(ast.flags, 'i');

  const precedence = run([
    '-e', String.raw`/(?<all>.)\k<all>/s`, '--table', 'all', '--compat', '--optimize',
  ]);
  assert.equal(precedence.status, 0);
  assert.match(precedence.stdout, /Optimized:/);
  assert.doesNotMatch(precedence.stdout, /Compat:|transition table/);

  const compatOverTable = run([
    '-e', String.raw`/(?<all>.)\k<all>/s`, '--table', 'all', '--compat', '--loc',
  ]);
  assert.equal(compatOverTable.status, 0);
  assert.match(compatOverTable.stdout, /Compat:/);
  assert.doesNotMatch(compatOverTable.stdout, /transition table|"loc"/);
});

test('unknown options and operands expose upstream non-strict parsing', () => {
  const result = run(['-e', '/a/', '--misspelled-operation', 'extra-operand']);
  assert.equal(result.status, 0);
  assert.equal(result.stderr, '');
  assert.equal(JSON.parse(result.stdout).body.value, 'a');
});

test('native failures retain upstream statuses and diagnostics', () => {
  for (const args of [
    [],
    ['-e'],
    ['-e', 'a|b'],
    ['-e', '/(/'],
    ['-e', '/(/', '--optimize'],
    ['-e', '/(/', '--compat'],
    ['-e', '/a/', '--table', 'bogus'],
  ]) {
    const result = run(args);
    assert.equal(result.status, 1, `${args.join(' ')} should fail`);
    assert.equal(result.stdout, '');
    assert.notEqual(result.stderr, '');
  }

  const piped = run([], {input: '/a/'});
  assert.equal(piped.status, 1);
  assert.equal(piped.stdout, '');
  assert.match(piped.stderr, /Missing required argument: expression/);
});

test('unsupported table constructs retain already-written native output', () => {
  const result = run(['-e', '/a(?=b)/', '--table', 'all']);
  assert.equal(result.status, 1);
  assert.match(result.stdout, /> - starting/);
  assert.notEqual(result.stderr, '');
});

test('arguments are passed directly without shell reconstruction', () => {
  const expression = String.raw`/a b; $HOME ! é \//u`;
  const result = run(['-e', expression]);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(JSON.parse(result.stdout).type, 'RegExp');
  assert.doesNotMatch(result.stdout, /\x1b\[/);
});

