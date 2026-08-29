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
use Symbol qw(gensym);
use Test::More;

my $ROOT = abs_path(File::Spec->catdir($Bin, '..'));
my $CLI = File::Spec->catfile($ROOT, 'bin', 'regex-presuf');

sub run_cli {
    my (%args) = @_;
    my $argv = $args{args} || [];
    my $stdin = exists $args{stdin} ? $args{stdin} : '';
    my $cwd = $args{cwd} || $ROOT;
    my $command = $args{command} || [$^X, $CLI];
    local %ENV = %ENV;
    @ENV{keys %{$args{env}}} = values %{$args{env}} if $args{env};
    my $old_cwd = getcwd();
    chdir $cwd or die "cannot chdir to $cwd: $!";
    my $stderr = gensym;
    my ($child_in, $child_out);
    my $pid = open3($child_in, $child_out, $stderr, @$command, @$argv);
    chdir $old_cwd or die "cannot restore cwd: $!";
    binmode $_, ':raw' for $child_in, $child_out, $stderr;
    print {$child_in} $stdin if length $stdin;
    close $child_in or die "cannot close child stdin: $!";
    local $/;
    my $stdout = <$child_out>;
    my $error = <$stderr>;
    waitpid $pid, 0;
    return {
        stdout => defined $stdout ? $stdout : '',
        stderr => defined $error ? $error : '',
        status => $? >> 8,
        signal => $? & 127,
    };
}

sub assert_result {
    my ($result, $status, $stdout, $stderr, $name) = @_;
    is($result->{signal}, 0, "$name: no signal");
    is($result->{status}, $status, "$name: status");
    is($result->{stdout}, $stdout, "$name: stdout");
    is($result->{stderr}, $stderr, "$name: stderr");
}

sub body_from {
    my ($result, $name) = @_;
    is($result->{status}, 0, "$name succeeds");
    is($result->{stderr}, '', "$name leaves stderr empty");
    my $body = decode('UTF-8', $result->{stdout});
    chop $body;
    return $body;
}

sub assert_full_matches {
    my ($body, $positives, $negatives, $name) = @_;
    my $regex = qr/\A(?:$body)\z/;
    ok($_ =~ $regex, "$name matches literal sample") for @$positives;
    ok($_ !~ $regex, "$name rejects negative") for @$negatives;
}

my $help = run_cli(args => ['--help']);
is($help->{status}, 0, 'help exits 0');
like($help->{stdout}, qr/^Usage: regex-presuf /, 'help prints usage');
like($help->{stdout}, qr/prefix, both, or suffix/, 'help lists strategies');
is($help->{stderr}, '', 'help leaves stderr empty');
assert_result(
    run_cli(args => ['--version']), 0,
    "regex-presuf (Regex::PreSuf 1.17)\n", '', 'version',
);

assert_result(
    run_cli(stdin => "foobar\nfooxar\nfoozap\n"),
    0, "foo(?:bar|xar|zap)\n", '', 'documented prefix example',
);
assert_result(
    run_cli(args => ['--strategy', 'both', qw(foobar fooxar foozap)]),
    0, "foo(?:zap|[bx]ar)\n", '', 'documented both example',
);
assert_result(
    run_cli(args => ['--anychar', 'foo.bar', 'fooxbar']),
    0, "foo.bar\n", '', 'documented anychar example',
);

my ($first_handle, $first_path) = tempfile();
binmode $first_handle, ':raw';
print {$first_handle} "foobar\r\nfooxar\n";
close $first_handle;
my ($second_handle, $second_path) = tempfile();
binmode $second_handle, ':raw';
print {$second_handle} 'foozap';
close $second_handle;
my $files = run_cli(args => ['--input', $first_path, '--input', $second_path]);
is($files->{stdout}, "foo(?:bar|xar|zap)\n", 'repeated files delimit records');
is($files->{status}, 0, 'repeated files succeed');
my $explicit = run_cli(
    args => ['--input', '-'], stdin => "foobar\nfooxar\nfoozap\n",
);
is($explicit->{stdout}, $files->{stdout}, 'explicit stdin matches files');

assert_result(run_cli(args => ['']), 0, "\n", '', 'empty positional sample');
assert_result(run_cli(stdin => "\n"), 0, "\n", '', 'one blank stdin record');
assert_result(
    run_cli(args => ['', 'foo']), 0, "(?:foo)?\n", '', 'empty plus nonempty sample',
);

my @metacharacters = (
    'a.b', 'a*b', 'a+b', 'a?b', 'a[b', 'a(b', 'a^b', 'a$b',
    'a/b', 'a\\b', '(?{danger})', '(??{danger})',
);
my $meta_body = body_from(run_cli(args => \@metacharacters), 'metacharacters');
assert_full_matches($meta_body, \@metacharacters, ['ab', 'axb', 'danger'],
    'default metacharacter handling');

my $anychar_body = body_from(
    run_cli(args => ['--anychar', 'foo.bar', 'fooxbar']), 'anychar semantics',
);
assert_full_matches(
    $anychar_body,
    [qw(foo.bar fooxbar fooZbar)],
    [qw(foobar fooxybar)],
    'anychar semantics',
);

my @unicode = ("caf\x{e9}", "caf\x{e8}");
my $unicode_body = body_from(
    run_cli(args => [map { encode('UTF-8', $_) } @unicode]), 'Unicode inference',
);
is($unicode_body, "caf[\x{e8}\x{e9}]", 'Unicode rendering is stable');
assert_full_matches($unicode_body, \@unicode, ['cafe'], 'Unicode inference');

my @whitespace = (' leading', 'trailing ', "line\nbreak", "tab\tstop");
my $space_body = body_from(run_cli(args => \@whitespace), 'whitespace samples');
assert_full_matches($space_body, \@whitespace, ['leading', 'trailing'],
    'whitespace samples');

my $one = run_cli(args => ['duplicate']);
my $dupes = run_cli(args => [qw(duplicate duplicate duplicate)]);
is($dupes->{stdout}, $one->{stdout}, 'duplicates collapse upstream');

for my $strategy (qw(prefix both suffix)) {
    my $body = body_from(
        run_cli(args => ['--strategy', $strategy, qw(foobar xxbar bazbar)]),
        "$strategy strategy",
    );
    assert_full_matches($body, [qw(foobar xxbar bazbar)], [qw(foo bar)],
        "$strategy strategy");
}

my $outside = tempdir(CLEANUP => 1);
my $outside_result = run_cli(args => [qw(foobar fooxar)], cwd => $outside);
is($outside_result->{status}, 0, 'command works outside checkout');
is($outside_result->{stdout}, "foo[bx]ar\n", 'outside-cwd output');

for my $failure (
    ['unknown option', ['--bogus', 'foo'], qr/Unknown option/],
    ['missing strategy argument', ['--strategy'], qr/requires an argument/],
    ['repeated strategy', ['--strategy', 'prefix', '--strategy', 'both', 'foo'],
        qr/may be supplied only once/],
    ['invalid strategy', ['--strategy', 'middle', 'foo'], qr/invalid strategy/],
    ['conflicting sources', ['--input', $first_path, 'foo'], qr/mutually exclusive/],
    ['repeated stdin', ['--input', '-', '--input', '-'], qr/at most once/],
) {
    my ($name, $args, $message) = @$failure;
    my $result = run_cli(args => $args);
    is($result->{status}, 2, "$name exits 2");
    is($result->{stdout}, '', "$name leaves stdout empty");
    like($result->{stderr}, qr/^regex-presuf: .*${message}/s,
        "$name has prefixed diagnostic");
}

for my $zero (
    ['implicit zero bytes', {stdin => ''}],
    ['explicit zero bytes', {args => ['--input', '-'], stdin => ''}],
) {
    my ($name, $invocation) = @$zero;
    my $result = run_cli(%$invocation);
    is($result->{status}, 2, "$name exits 2");
    is($result->{stdout}, '', "$name leaves stdout empty");
    like($result->{stderr}, qr/no samples supplied/, "$name is diagnosed");
}

my $missing = run_cli(args => ['--input', "$outside/missing"]);
is($missing->{status}, 1, 'missing input exits 1');
is($missing->{stdout}, '', 'missing input leaves stdout empty');
like($missing->{stderr}, qr/cannot open input file/, 'missing input is diagnosed');

my ($bad_handle, $bad_path) = tempfile();
binmode $bad_handle, ':raw';
print {$bad_handle} "\xFF\n";
close $bad_handle;
for my $bad (
    ['argv', {args => ["\xFF"]}],
    ['file', {args => ['--input', $bad_path]}],
    ['stdin', {stdin => "\xFF\n"}],
) {
    my ($name, $invocation) = @$bad;
    my $result = run_cli(%$invocation);
    is($result->{status}, 1, "invalid UTF-8 $name exits 1");
    is($result->{stdout}, '', "invalid UTF-8 $name leaves stdout empty");
    like($result->{stderr}, qr/not valid UTF-8/, "invalid UTF-8 $name diagnosed");
}

my $sentinel = File::Spec->catfile($outside, 'regex-code-ran');
my $code = '(?{open my $fh, q{>}, q{' . $sentinel . '}; print {$fh} q{x}})';
my $code_body = body_from(run_cli(args => [$code]), 'regex code literal');
assert_full_matches($code_body, [$code], [], 'regex code literal');
ok(!-e $sentinel, 'sample text did not execute as Perl code');

my ($write_stderr, $write_stderr_path) = tempfile();
binmode $write_stderr, ':raw';
pipe my $closed_reader, my $broken_writer or die "cannot create pipe: $!";
close $closed_reader;
my $write_pid = fork();
die "cannot fork: $!" unless defined $write_pid;
if ($write_pid == 0) {
    open STDOUT, '>&', $broken_writer or die "cannot redirect stdout: $!";
    open STDERR, '>&', $write_stderr or die "cannot redirect stderr: $!";
    close $broken_writer;
    exec $^X, $CLI, 'foo';
    die "cannot exec $CLI: $!";
}
close $broken_writer;
waitpid $write_pid, 0;
is($? >> 8, 1, 'stdout write failure exits 1');
seek $write_stderr, 0, 0 or die "cannot rewind write stderr: $!";
{
    local $/;
    my $message = <$write_stderr>;
    like($message, qr/^regex-presuf: cannot write stdout:/,
        'stdout write failure is diagnosed');
}

my $fake_root = tempdir(CLEANUP => 1);
my $fake_bin = File::Spec->catdir($fake_root, 'bin');
my $fake_module_dir = File::Spec->catdir($fake_root, 'local', 'lib', 'perl5', 'Regex');
make_path($fake_bin, $fake_module_dir);
my $fake_cli = File::Spec->catfile($fake_bin, 'regex-presuf');
open my $source, '<:raw', $CLI or die "cannot open $CLI: $!";
open my $copy, '>:raw', $fake_cli or die "cannot create $fake_cli: $!";
while (read $source, my $buffer, 64 * 1024) { print {$copy} $buffer }
close $source;
close $copy;

my $hidden_root = tempdir(CLEANUP => 1);
my $hidden_bin = File::Spec->catdir($hidden_root, 'bin');
make_path($hidden_bin);
my $hidden_cli = File::Spec->catfile($hidden_bin, 'regex-presuf');
open $source, '<:raw', $CLI or die "cannot reopen $CLI: $!";
open $copy, '>:raw', $hidden_cli or die "cannot create $hidden_cli: $!";
while (read $source, my $buffer, 64 * 1024) { print {$copy} $buffer }
close $source;
close $copy;
my $missing_help = run_cli(command => [$^X, $hidden_cli], args => ['--help']);
is($missing_help->{status}, 0, 'help works without dependency');
my $missing_dependency = run_cli(command => [$^X, $hidden_cli], args => ['foo']);
assert_result(
    $missing_dependency, 1, '',
    "regex-presuf: Regex::PreSuf 1.17 is not installed; run cpanm --local-lib-contained local --installdeps .\n",
    'missing dependency',
);

my $fake_module = File::Spec->catfile($fake_module_dir, 'PreSuf.pm');
open my $module, '>:raw', $fake_module or die "cannot create fake module: $!";
print {$module} <<'FAKE';
package Regex::PreSuf;
our $VERSION = '1.17';
sub presuf {
    my ($options, @samples) = @_;
    open my $calls, '>>:raw', $ENV{PRESUF_CALLS} or die "call log: $!";
    print {$calls} join(',', map { "$_=$options->{$_}" } sort keys %$options),
        ';', join('|', @samples), "\n";
    close $calls;
    die "forced upstream failure\n" if $ENV{PRESUF_FAIL};
    return '(' if $ENV{PRESUF_INVALID};
    return 'fake';
}
1;
FAKE
close $module;
my $calls_path = File::Spec->catfile($fake_root, 'calls');
my $single_call = run_cli(
    command => [$^X, $fake_cli],
    args => ['--strategy', 'both', '--anychar', qw(foo.bar fooxbar)],
    env => {PRESUF_CALLS => $calls_path},
);
assert_result($single_call, 0, "fake\n", '', 'controlled upstream call');
open my $calls, '<:raw', $calls_path or die "cannot read call log: $!";
my @calls = <$calls>;
close $calls;
is_deeply(\@calls, ["anychar=1,suffixes=1;foo.bar|fooxbar\n"],
    'presuf is called once with minimal mapped options and ordered samples');

for my $forced (
    ['exception', {PRESUF_CALLS => $calls_path, PRESUF_FAIL => 1}, qr/forced upstream/],
    ['invalid regex', {PRESUF_CALLS => $calls_path, PRESUF_INVALID => 1},
        qr/generated regex did not compile/],
) {
    my ($name, $env, $message) = @$forced;
    my $result = run_cli(command => [$^X, $fake_cli], args => ['foo'], env => $env);
    is($result->{status}, 1, "forced $name exits 1");
    is($result->{stdout}, '', "forced $name leaves stdout empty");
    like($result->{stderr}, $message, "forced $name is diagnosed");
}

done_testing();
