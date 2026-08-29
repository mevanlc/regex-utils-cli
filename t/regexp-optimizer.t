use v5.8.1;
use strict;
use warnings;
use utf8;

use Cwd qw(abs_path getcwd);
use Encode qw(decode encode);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir tempfile);
use FindBin qw($Bin);
use IPC::Open3 qw(open3);
use POSIX qw(SIGPIPE);
use Symbol qw(gensym);
use Test::More;

my $ROOT = abs_path(File::Spec->catdir($Bin, '..'));
my $CLI = File::Spec->catfile($ROOT, 'bin', 'regexp-optimizer');

sub run_cli {
    my (%args) = @_;
    my $argv = $args{args} || [];
    my $stdin = exists $args{stdin} ? $args{stdin} : '';
    my $cwd = $args{cwd} || $ROOT;
    my $command = $args{command} || [$^X, $CLI];
    local %ENV = %ENV;
    if ($args{env}) {
        @ENV{keys %{$args{env}}} = values %{$args{env}};
    }

    my $old_cwd = getcwd();
    chdir $cwd or die "cannot chdir to $cwd: $!";
    my $stderr = gensym;
    my ($child_in, $child_out);
    my $pid = open3($child_in, $child_out, $stderr, @$command, @$argv);
    chdir $old_cwd or die "cannot restore cwd to $old_cwd: $!";

    binmode $child_in, ':raw';
    binmode $child_out, ':raw';
    binmode $stderr, ':raw';
    print {$child_in} $stdin if length $stdin;
    close $child_in or die "cannot close child stdin: $!";

    local $/;
    my $stdout_bytes = <$child_out>;
    my $stderr_bytes = <$stderr>;
    $stdout_bytes = '' unless defined $stdout_bytes;
    $stderr_bytes = '' unless defined $stderr_bytes;
    waitpid $pid, 0;
    my $wait_status = $?;

    return {
        stdout => $stdout_bytes,
        stderr => $stderr_bytes,
        status => $wait_status >> 8,
        signal => $wait_status & 127,
    };
}

sub assert_result {
    my ($result, $status, $stdout, $stderr, $name) = @_;
    is($result->{signal}, 0, "$name: no signal");
    is($result->{status}, $status, "$name: status");
    is($result->{stdout}, $stdout, "$name: stdout");
    is($result->{stderr}, $stderr, "$name: stderr");
}

my $help = run_cli(args => ['--help']);
is($help->{status}, 0, 'help exits successfully');
like($help->{stdout}, qr/^Usage: regexp-optimizer /, 'help prints usage');
like($help->{stdout}, qr/--flags FLAGS/, 'help lists flags');
is($help->{stderr}, '', 'help leaves stderr empty');

assert_result(
    run_cli(args => ['--version']),
    0,
    "regexp-optimizer (Regexp::Optimizer 0.23)\n",
    '',
    'version',
);

assert_result(
    run_cli(args => ['foobar|fooxar|foozap']),
    0,
    "(?^:foo(?:[bx]ar|zap))\n",
    '',
    'documented optimization',
);

assert_result(
    run_cli(args => ['--flags', 'i', 'foo|bar']),
    0,
    "(?^:(?i:(?:bar|foo)))\n",
    '',
    'case-insensitive optimization',
);

assert_result(
    run_cli(args => ['--flags', 'smi', 'foo|bar']),
    0,
    "(?^:(?ims:(?:bar|foo)))\n",
    '',
    'flags are canonicalized',
);

my $stdin_pattern = encode('UTF-8', 'café|cafè');
my $stdin_result = run_cli(stdin => $stdin_pattern);
is($stdin_result->{status}, 0, 'Unicode stdin succeeds');
is($stdin_result->{stderr}, '', 'Unicode stdin leaves stderr empty');
my $unicode_output = decode('UTF-8', $stdin_result->{stdout});
like($unicode_output, qr/caf/, 'Unicode output is valid UTF-8');
chomp $unicode_output;
my $unicode_regex = qr/\A(?:$unicode_output)\z/;
ok('café' =~ $unicode_regex, 'Unicode output matches first positive');
ok('cafè' =~ $unicode_regex, 'Unicode output matches second positive');
ok('cafe' !~ $unicode_regex, 'Unicode output rejects ASCII negative');

my $nul_result = run_cli(stdin => "a\0b|c");
is($nul_result->{status}, 0, 'NUL-containing pattern succeeds');
is($nul_result->{stderr}, '', 'NUL-containing pattern has no stderr');
my $nul_output = decode('UTF-8', $nul_result->{stdout});
chomp $nul_output;
my $nul_regex = qr/\A(?:$nul_output)\z/;
ok("a\0b" =~ $nul_regex, 'NUL-containing output matches NUL branch');
ok('c' =~ $nul_regex, 'NUL-containing output matches alternate branch');

assert_result(
    run_cli(stdin => "foo\n"),
    0,
    "foo\n\n",
    '',
    'trailing input newline is preserved',
);

my ($input_handle, $input_path) = tempfile();
binmode $input_handle, ':raw';
print {$input_handle} 'foobar|fooxar|foozap';
close $input_handle;
my $file_result = run_cli(args => ['--input', $input_path]);
is($file_result->{stdout}, "(?^:foo(?:[bx]ar|zap))\n", 'file input matches argv');
is($file_result->{status}, 0, 'file input succeeds');

my $explicit_stdin = run_cli(
    args => ['--input', '-'],
    stdin => 'foobar|fooxar|foozap',
);
is($explicit_stdin->{stdout}, $file_result->{stdout}, 'explicit stdin matches file');
is($explicit_stdin->{status}, 0, 'explicit stdin succeeds');

assert_result(
    run_cli(stdin => ''),
    0,
    "\n",
    '',
    'empty redirected input',
);

assert_result(
    run_cli(args => ['']),
    0,
    "\n",
    '',
    'empty positional pattern',
);

my $outside = tempdir(CLEANUP => 1);
my $outside_result = run_cli(
    args => ['foobar|fooxar|foozap'],
    cwd => $outside,
);
is($outside_result->{status}, 0, 'command works outside checkout');
is($outside_result->{stdout}, "(?^:foo(?:[bx]ar|zap))\n", 'outside-cwd output');

for my $case (
    ['nested groups', '(?:foo|bar)(?:baz|quux)', [qw(foobaz barquux)], [qw(foo baz)]],
    ['metacharacters', 'a(?:\+|\*)b', ['a+b', 'a*b'], ['ab']],
    ['x mode', 'foo | bar', ['foo', 'bar'], ['baz'], 'x'],
) {
    my ($name, $body, $positives, $negatives, $case_flags) = @$case;
    my @args = defined $case_flags ? ('--flags', $case_flags, $body) : ($body);
    my $result = run_cli(args => \@args);
    is($result->{status}, 0, "$name optimizes");
    is($result->{stderr}, '', "$name has no stderr");
    my $rendered = decode('UTF-8', $result->{stdout});
    chomp $rendered;
    my $original_source = defined $case_flags
        ? "(?$case_flags:$body" . (index($case_flags, 'x') >= 0 ? "\n" : '') . ')'
        : $body;
    my $original = qr/$original_source/;
    my $optimized = qr/$rendered/;
    for my $sample (@$positives, @$negatives) {
        is(
            ($sample =~ $optimized ? 1 : 0),
            ($sample =~ $original ? 1 : 0),
            "$name preserves match result for '$sample'",
        );
    }
}

my $escaped_pipe = run_cli(args => ['foo\|bar|baz']);
assert_result(
    $escaped_pipe,
    0,
    "(?^:(?:ba[rz]|foo))\n",
    '',
    'upstream escaped-pipe behavior',
);
my $escaped_original = qr/foo\|bar|baz/;
my $escaped_rendered = decode('UTF-8', $escaped_pipe->{stdout});
chomp $escaped_rendered;
my $escaped_optimized = qr/$escaped_rendered/;
ok('foo|bar' =~ /\A(?:$escaped_original)\z/,
    'escaped-pipe original fully matches literal pipe');
ok('foo|bar' !~ /\A(?:$escaped_optimized)\z/,
    'upstream optimization loses escaped-pipe full match');
ok('foo' !~ /\A(?:$escaped_original)\z/,
    'escaped-pipe original fully rejects foo');
ok('foo' =~ /\A(?:$escaped_optimized)\z/,
    'upstream optimization broadens to a full foo match');

my $x_comment = run_cli(args => ['--flags', 'x', 'foo | bar # comment']);
is($x_comment->{status}, 1, 'upstream x-comment failure exits 1');
is($x_comment->{stdout}, '', 'upstream x-comment failure leaves stdout empty');
like($x_comment->{stderr}, qr/^regexp-optimizer: optimization failed:/,
    'upstream x-comment failure is attributed to optimization');

my $first_pass = run_cli(args => ['foo|bar']);
my $first_body = decode('UTF-8', $first_pass->{stdout});
chomp $first_body;
my $second_pass = run_cli(args => [$first_body]);
is($second_pass->{status}, 0, 'second optimization pass succeeds');
my $second_body = decode('UTF-8', $second_pass->{stdout});
chomp $second_body;
my $first_regex = qr/$first_body/;
my $second_regex = qr/$second_body/;
for my $sample (qw(foo bar baz food)) {
    is(
        ($sample =~ $second_regex ? 1 : 0),
        ($sample =~ $first_regex ? 1 : 0),
        "second pass remains semantically equivalent for '$sample'",
    );
}

my ($pipe_stderr, $pipe_stderr_path) = tempfile();
binmode $pipe_stderr, ':raw';
pipe my $closed_reader, my $broken_writer or die "cannot create pipe: $!";
close $closed_reader;
my $pipe_pid = fork();
die "cannot fork: $!" unless defined $pipe_pid;
if ($pipe_pid == 0) {
    open STDOUT, '>&', $broken_writer or die "cannot redirect stdout: $!";
    open STDERR, '>&', $pipe_stderr or die "cannot redirect stderr: $!";
    close $broken_writer;
    exec $^X, $CLI, 'foo|bar';
    die "cannot exec $CLI: $!";
}
close $broken_writer;
waitpid $pipe_pid, 0;
my $pipe_status = $?;
seek $pipe_stderr, 0, 0 or die "cannot rewind pipe stderr: $!";
my $pipe_diagnostic;
{
    local $/;
    $pipe_diagnostic = <$pipe_stderr>;
}
$pipe_diagnostic = '' unless defined $pipe_diagnostic;
is($pipe_status & 127, SIGPIPE, 'closed stdout uses normal SIGPIPE handling');
is($pipe_diagnostic, '', 'broken pipe adds no wrapper diagnostic');

for my $failure (
    ['unknown option', ['--bogus'], 2],
    ['duplicate flags', ['--flags', 'ii', 'foo'], 2],
    ['unsupported flag', ['--flags', 'q', 'foo'], 2],
    ['repeated flags option', ['--flags', 'i', '--flags', 'm', 'foo'], 2],
    ['repeated input option', ['--input', $input_path, '--input', $input_path], 2],
    ['multiple patterns', ['foo', 'bar'], 2],
    ['conflicting sources', ['--input', $input_path, 'foo'], 2],
    ['missing file', ['--input', "$outside/does-not-exist"], 1],
    ['directory input', ['--input', $outside], 1],
    ['invalid regex', ['(unclosed'], 1],
) {
    my ($name, $args, $status) = @$failure;
    my $result = run_cli(args => $args);
    is($result->{status}, $status, "$name has expected status");
    is($result->{stdout}, '', "$name leaves stdout empty");
    like($result->{stderr}, qr/^regexp-optimizer:/, "$name prefixes diagnostic");
}

my ($bad_handle, $bad_path) = tempfile();
binmode $bad_handle, ':raw';
print {$bad_handle} "\xFF";
close $bad_handle;
for my $invalid_utf8 (
    ['argv', {args => ["\xFF"]}],
    ['file', {args => ['--input', $bad_path]}],
    ['stdin', {stdin => "\xFF"}],
) {
    my ($name, $invocation) = @$invalid_utf8;
    my $result = run_cli(%$invocation);
    is($result->{status}, 1, "invalid UTF-8 $name exits 1");
    is($result->{stdout}, '', "invalid UTF-8 $name leaves stdout empty");
    like($result->{stderr}, qr/^regexp-optimizer: .*not valid UTF-8:/,
        "invalid UTF-8 $name is diagnosed");
}

my $sentinel = File::Spec->catfile($outside, 'regex-code-ran');
my $code_pattern = '(?{open my $fh, q{>}, q{' . $sentinel . '}; print {$fh} q{x}})';
my $code_result = run_cli(args => [$code_pattern]);
is($code_result->{status}, 1, 'regex code assertion is rejected');
is($code_result->{stdout}, '', 'regex code assertion leaves stdout empty');
ok(!-e $sentinel, 'regex-supplied code did not execute');

my $inherited_eval = run_cli(
    args => [$code_pattern],
    env => {PERL5OPT => '-Mre=eval'},
);
is($inherited_eval->{status}, 1, 'inherited re eval still rejects code assertion');
is($inherited_eval->{stdout}, '', 'inherited re eval leaves stdout empty');
ok(!-e $sentinel, 'inherited re eval cannot enable regex-supplied code');

my $fake_root = tempdir(CLEANUP => 1);
my $fake_bin = File::Spec->catdir($fake_root, 'bin');
make_path($fake_bin);
my $fake_cli = File::Spec->catfile($fake_bin, 'regexp-optimizer');
open my $source, '<:raw', $CLI or die "cannot open $CLI: $!";
open my $copy, '>:raw', $fake_cli or die "cannot create $fake_cli: $!";
while (read $source, my $buffer, 64 * 1024) {
    print {$copy} $buffer;
}
close $source;
close $copy;

my $missing_help = run_cli(command => [$^X, $fake_cli], args => ['--help']);
is($missing_help->{status}, 0, 'help works before dependency bootstrap');
is($missing_help->{stderr}, '', 'bootstrap-free help has no stderr');

my $missing_dependency = run_cli(
    command => [$^X, $fake_cli],
    args => ['foo'],
);
assert_result(
    $missing_dependency,
    1,
    '',
    "regexp-optimizer: Regexp::Optimizer 0.23 is not installed; run cpanm --local-lib-contained local --installdeps .\n",
    'missing dependency',
);

my $fake_module_dir = File::Spec->catdir($fake_root, 'local', 'lib', 'perl5', 'Regexp');
make_path($fake_module_dir);
my $fake_module = File::Spec->catfile($fake_module_dir, 'Optimizer.pm');
open my $module_file, '>:raw', $fake_module or die "cannot create $fake_module: $!";
print {$module_file} <<'FAKE_MODULE';
package Regexp::Optimizer;
use strict;
use warnings;
our $VERSION = '0.23';
sub new { return bless {}, shift }
sub optimize {
    my ($self, $regex) = @_;
    open my $count, '>>:raw', $ENV{REGEXP_OPTIMIZER_CALLS}
        or die "cannot record optimize call: $!";
    print {$count} "called\n";
    close $count;
    return $regex;
}
1;
FAKE_MODULE
close $module_file;

my $call_record = File::Spec->catfile($fake_root, 'optimize-calls');
my $single_call = run_cli(
    command => [$^X, $fake_cli],
    args => ['foo|bar'],
    env => {REGEXP_OPTIMIZER_CALLS => $call_record},
);
is($single_call->{status}, 0, 'controlled optimizer invocation succeeds');
open my $call_file, '<:raw', $call_record or die "cannot open $call_record: $!";
my @calls = <$call_file>;
close $call_file;
is_deeply(\@calls, ["called\n"], 'optimizer is called exactly once');

open $module_file, '>:raw', $fake_module or die "cannot replace $fake_module: $!";
print {$module_file} "package Regexp::Optimizer; our \$VERSION = '0.22'; 1;\n";
close $module_file;
my $wrong_version = run_cli(command => [$^X, $fake_cli], args => ['foo']);
assert_result(
    $wrong_version,
    1,
    '',
    "regexp-optimizer: Regexp::Optimizer 0.23 is not installed; run cpanm --local-lib-contained local --installdeps .\n",
    'wrong dependency version',
);

done_testing();
