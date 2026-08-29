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
my $CLI = File::Spec->catfile($ROOT, 'bin', 'regexp-assemble');

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
    chomp $body;
    return $body;
}

sub assert_full_matches {
    my ($body, $positives, $negatives, $name) = @_;
    my $regex = qr/\A(?:$body)\z/;
    ok($_ =~ $regex, "$name matches '$_'") for @$positives;
    ok($_ !~ $regex, "$name rejects '$_'") for @$negatives;
}

my $top_help = run_cli(args => ['--help']);
is($top_help->{status}, 0, 'top help exits 0');
like($top_help->{stdout}, qr/regexp-assemble assemble/, 'top help lists assemble');
like($top_help->{stdout}, qr/regexp-assemble match/, 'top help lists match');
is($top_help->{stderr}, '', 'top help leaves stderr empty');

for my $command (qw(assemble match)) {
    my $help = run_cli(args => [$command, '--help']);
    is($help->{status}, 0, "$command help exits 0");
    like($help->{stdout}, qr/^Usage: regexp-assemble $command /,
        "$command help has command usage");
    is($help->{stderr}, '', "$command help leaves stderr empty");
}

assert_result(
    run_cli(args => ['--version']), 0,
    "regexp-assemble (Regexp::Assemble 0.38)\n", '', 'top version',
);
assert_result(
    run_cli(args => ['assemble', '--version']), 0,
    "regexp-assemble (Regexp::Assemble 0.38)\n", '', 'command version',
);

assert_result(
    run_cli(args => ['assemble', qw(foobar fooxar foozap)]),
    0, "foo(?:[bx]ar|zap)\n", '', 'documented assembly',
);
assert_result(
    run_cli(args => ['assemble', '--literal', 'a.b', 'a-b']),
    0, "a[-.]b\n", '', 'documented literal assembly',
);
assert_result(
    run_cli(args => ['match', '--text', 'xxfooxaryy', qw(foobar fooxar foozap)]),
    0, "fooxar\n", '', 'documented match',
);
assert_result(
    run_cli(args => ['match', '--text', 'none', qw(foo bar)]),
    1, '', '', 'valid non-match',
);
assert_result(
    run_cli(args => ['match', '--text', 'abc', '^', 'z']),
    0, "\n", '', 'zero-width match',
);

my ($first_handle, $first_path) = tempfile();
binmode $first_handle, ':raw';
print {$first_handle} "foobar\r\nfooxar\n";
close $first_handle;
my ($second_handle, $second_path) = tempfile();
binmode $second_handle, ':raw';
print {$second_handle} 'foozap';
close $second_handle;
my $files = run_cli(args => ['assemble', '--input', $first_path, '--input', $second_path]);
is($files->{stdout}, "foo(?:[bx]ar|zap)\n", 'repeated files preserve record semantics');
is($files->{status}, 0, 'repeated files succeed');
my $stdin = run_cli(args => ['assemble'], stdin => "foobar\nfooxar\nfoozap\n");
is($stdin->{stdout}, $files->{stdout}, 'implicit stdin matches files');
my $explicit_stdin = run_cli(
    args => ['assemble', '--input', '-'],
    stdin => "foobar\nfooxar\nfoozap\n",
);
is($explicit_stdin->{stdout}, $files->{stdout}, 'explicit stdin matches files');

my $duplicates = run_cli(args => ['assemble', qw(foo foo bar)]);
is($duplicates->{stdout}, "(?:bar|foo)\n", 'duplicates do not duplicate a branch');

for my $anchor (
    [none => qr/^(?:\(\?:bar\|foo\)|\(\?:foo\|bar\))$/],
    [word => qr/^\\b.*\\b$/],
    [line => qr/^\^.*\$$/],
    [string => qr/^\\A.*\\Z$/],
    ['string-absolute' => qr/^\\A.*\\z$/],
) {
    my ($kind, $expected) = @$anchor;
    my $body = body_from(
        run_cli(args => ['assemble', '--anchor', $kind, qw(foo bar)]),
        "$kind anchor",
    );
    like($body, $expected, "$kind anchor maps to upstream anchors");
}

my $flagged = body_from(
    run_cli(args => ['assemble', '--flags', 'smi', qw(foo bar)]),
    'flagged assembly',
);
like($flagged, qr/^\(\?ims:/, 'flags are canonicalized and preserved');

for my $case (
    ['default reduction', ['assemble', 'abcd', 'aecd'], [qw(abcd aecd)], [qw(acd)]],
    ['no reduction', ['assemble', '--no-reduce', 'abcd', 'aecd'], [qw(abcd aecd)], [qw(acd)]],
    ['lookahead', ['assemble', '--lookahead', 'bob', 'alice', 'charles'],
        [qw(bob alice charles)], [qw(alicee)]],
    ['plus unrolling', ['assemble', '--unroll-plus', 'ab+c', 'ab+d'],
        [qw(abc abbc abd abbd)], [qw(ac)]],
    ['meta folding', ['assemble', '\\d', '\\D'], ['0', 'x'], []],
    ['no meta folding', ['assemble', '--no-fold-meta-pairs', '\\d', '\\D'],
        ['0', 'x'], []],
) {
    my ($name, $args, $positives, $negatives) = @$case;
    my $body = body_from(run_cli(args => $args), $name);
    assert_full_matches($body, $positives, $negatives, $name);
}

my $indented = body_from(
    run_cli(args => ['assemble', '--flags', 'x', '--indent', '2',
        qw(foobar fooxar fizzbar)]),
    'indented output',
);
like($indented, qr/\n/, 'indented x output spans lines');

my @literal_samples = ('a+b', 'a.b', ' space ', "caf\x{e9}");
my $literal_body = body_from(
    run_cli(args => ['assemble', '--literal', map { encode('UTF-8', $_) } @literal_samples]),
    'literal metacharacter and Unicode assembly',
);
assert_full_matches($literal_body, \@literal_samples, ['ab', 'cafe'], 'literal assembly');

my $text_file_handle;
my ($text_handle, $text_path) = tempfile();
binmode $text_handle, ':raw';
print {$text_handle} encode('UTF-8', "xx\ncaf\x{e9}\nyy");
close $text_handle;
assert_result(
    run_cli(args => ['match', '--text-file', $text_path, '--literal',
        encode('UTF-8', "caf\x{e9}")]),
    0, encode('UTF-8', "caf\x{e9}\n"), '', 'Unicode text file match',
);

my $outside = tempdir(CLEANUP => 1);
my $outside_result = run_cli(
    args => ['assemble', qw(foobar fooxar foozap)], cwd => $outside,
);
is($outside_result->{status}, 0, 'command works outside checkout');
is($outside_result->{stdout}, "foo(?:[bx]ar|zap)\n", 'outside-cwd output');

for my $failure (
    ['missing command', [], qr/missing command/],
    ['unknown command', ['unknown'], qr/unknown command/],
    ['unknown option', ['assemble', '--bogus', 'foo'], qr/Unknown option/],
    ['duplicate flags', ['assemble', '--flags', 'ii', 'foo'], qr/invalid flags/],
    ['unsupported flag', ['assemble', '--flags', 'q', 'foo'], qr/invalid flags/],
    ['invalid anchor', ['assemble', '--anchor', 'file', 'foo'], qr/invalid anchor/],
    ['zero indent', ['assemble', '--flags', 'x', '--indent', '0', 'foo'], qr/greater than zero/],
    ['indent without x', ['assemble', '--indent', '2', 'foo'], qr/requires x/],
    ['indent with lookahead', ['assemble', '--flags', 'x', '--indent', '2',
        '--lookahead', 'foo'], qr/mutually exclusive/],
    ['conflicting pattern sources', ['assemble', '--input', $first_path, 'foo'],
        qr/mutually exclusive/],
    ['repeated stdin', ['assemble', '--input', '-', '--input', '-'],
        qr/at most once/],
    ['no records', ['assemble', '--input', $second_path . '.missing-empty'],
        qr/cannot open/],
    ['text with assemble', ['assemble', '--text', 'foo', 'foo'], qr/only with match/],
    ['match without text', ['match', 'foo'], qr/requires exactly one/],
    ['match with two text sources', ['match', '--text', 'foo', '--text-file', $text_path,
        'foo'], qr/requires exactly one/],
    ['stdin text file', ['match', '--text-file', '-', 'foo'], qr/not supported/],
    ['empty positional', ['assemble', ''], qr/PATTERN 1 is empty/],
    ['invalid regex', ['assemble', '(unclosed'], qr/not a valid Perl/],
) {
    my ($name, $args, $message) = @$failure;
    my $result = run_cli(args => $args);
    is($result->{status}, 2, "$name exits 2");
    is($result->{stdout}, '', "$name leaves stdout empty");
    like($result->{stderr}, qr/^regexp-assemble: .*${message}/s,
        "$name has prefixed diagnostic");
}

my ($empty_handle, $empty_path) = tempfile();
close $empty_handle;
my $empty_file = run_cli(args => ['assemble', '--input', $empty_path]);
is($empty_file->{status}, 2, 'zero-record file exits 2');
like($empty_file->{stderr}, qr/no patterns supplied/, 'zero-record file is diagnosed');
my ($blank_handle, $blank_path) = tempfile();
print {$blank_handle} "foo\n\n";
close $blank_handle;
my $blank_file = run_cli(args => ['assemble', '--input', $blank_path]);
is($blank_file->{status}, 2, 'blank record exits 2');
like($blank_file->{stderr}, qr/line 2 is empty/, 'blank record has line attribution');

my ($bad_handle, $bad_path) = tempfile();
binmode $bad_handle, ':raw';
print {$bad_handle} "\xFF\n";
close $bad_handle;
for my $bad (
    ['argv', ['assemble', "\xFF"]],
    ['file', ['assemble', '--input', $bad_path]],
) {
    my ($name, $args) = @$bad;
    my $result = run_cli(args => $args);
    is($result->{status}, 2, "invalid UTF-8 $name exits 2");
    like($result->{stderr}, qr/not valid UTF-8/, "invalid UTF-8 $name diagnosed");
}

my $sentinel = File::Spec->catfile($outside, 'regex-code-ran');
my $code = '(?{open my $fh, q{>}, q{' . $sentinel . '}; print {$fh} q{x}})';
my $code_result = run_cli(args => ['assemble', $code]);
is($code_result->{status}, 2, 'regex code assertion is rejected');
ok(!-e $sentinel, 'regex-supplied code did not execute');
my $literal_code = body_from(
    run_cli(args => ['assemble', '--literal', $code]), 'literal code assertion',
);
assert_full_matches($literal_code, [$code], [], 'literal code assertion');
ok(!-e $sentinel, 'literal code sample did not execute');

my $fake_root = tempdir(CLEANUP => 1);
my $fake_bin = File::Spec->catdir($fake_root, 'bin');
make_path($fake_bin);
my $fake_cli = File::Spec->catfile($fake_bin, 'regexp-assemble');
open my $source, '<:raw', $CLI or die "cannot open $CLI: $!";
open my $copy, '>:raw', $fake_cli or die "cannot create $fake_cli: $!";
while (read $source, my $buffer, 64 * 1024) { print {$copy} $buffer }
close $source;
close $copy;
my $missing_help = run_cli(command => [$^X, $fake_cli], args => ['--help']);
is($missing_help->{status}, 0, 'help works without dependencies');
my $missing_dependency = run_cli(
    command => [$^X, $fake_cli], args => ['assemble', 'foo'],
);
assert_result(
    $missing_dependency, 2, '',
    "regexp-assemble: Regexp::Assemble 0.38 is not installed; run cpanm --local-lib-contained local --installdeps .\n",
    'missing dependency',
);

done_testing();
