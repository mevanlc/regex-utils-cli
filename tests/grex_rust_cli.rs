use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};

use regex::Regex;

#[cfg(unix)]
use std::os::unix::fs::{PermissionsExt, symlink};

static NEXT_TEMP: AtomicU64 = AtomicU64::new(0);

fn validate_grex(path: &Path) -> Result<(), String> {
    if !path.is_file() {
        return Err("run ./tools/install-grex-rust: project-local grex is missing".into());
    }
    let output = Command::new(path)
        .arg("--version")
        .output()
        .map_err(|error| format!("run ./tools/install-grex-rust: {error}"))?;
    if !output.status.success() || output.stdout != b"grex 1.4.6\n" || !output.stderr.is_empty() {
        return Err(
            "run ./tools/install-grex-rust: project-local grex has the wrong version".into(),
        );
    }
    Ok(())
}

fn grex_path() -> PathBuf {
    let path = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join(".cargo-home")
        .join("bin")
        .join("grex");
    validate_grex(&path).unwrap_or_else(|message| panic!("{message}"));
    path
}

fn grex() -> Command {
    Command::new(grex_path())
}

fn run(arguments: &[&str], stdin: Option<&[u8]>) -> Output {
    let mut command = grex();
    command.args(arguments);
    if stdin.is_some() {
        command.stdin(Stdio::piped());
    } else {
        command.stdin(Stdio::null());
    }
    let mut child = command
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    if let Some(input) = stdin {
        child.stdin.take().unwrap().write_all(input).unwrap();
    }
    child.wait_with_output().unwrap()
}

fn text(bytes: &[u8]) -> &str {
    std::str::from_utf8(bytes).unwrap()
}

fn assert_success(output: &Output) {
    assert!(output.status.success(), "stderr: {}", text(&output.stderr));
    assert!(output.stderr.is_empty(), "stderr: {}", text(&output.stderr));
    assert!(output.stdout.ends_with(b"\n"));
    assert!(!output.stdout.ends_with(b"\n\n"));
}

fn expression(output: &Output) -> &str {
    assert_success(output);
    text(&output.stdout).strip_suffix('\n').unwrap()
}

fn assert_language(expression: &str, positive: &[&str], negative: &[&str]) {
    let regex = Regex::new(expression).unwrap();
    for sample in positive {
        assert!(
            regex.is_match(sample),
            "{expression:?} did not match {sample:?}"
        );
    }
    for sample in negative {
        assert!(
            !regex.is_match(sample),
            "{expression:?} unexpectedly matched {sample:?}"
        );
    }
}

struct TempDir(PathBuf);

impl TempDir {
    fn new() -> Self {
        let unique = NEXT_TEMP.fetch_add(1, Ordering::Relaxed);
        let path =
            std::env::temp_dir().join(format!("grex-rust-test-{}-{unique}", std::process::id()));
        fs::create_dir(&path).unwrap();
        Self(path)
    }

    fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        fs::remove_dir_all(&self.0).unwrap();
    }
}

#[test]
fn native_help_version_and_combined_short_flags_are_available() {
    for option in ["-h", "--help"] {
        let output = run(&[option], None);
        assert_success(&output);
        let help = text(&output.stdout);
        for spelling in [
            "--file",
            "--digits",
            "--non-digits",
            "--spaces",
            "--non-spaces",
            "--words",
            "--non-words",
            "--escape",
            "--with-surrogates",
            "--repetitions",
            "--min-repetitions",
            "--min-substring-length",
            "--no-start-anchor",
            "--no-end-anchor",
            "--no-anchors",
            "--verbose",
            "--colorize",
            "--ignore-case",
            "--capture-groups",
        ] {
            assert!(help.contains(spelling), "help omitted {spelling}");
        }
    }

    for option in ["-v", "--version"] {
        let output = run(&[option], None);
        assert_success(&output);
        assert_eq!(text(&output.stdout), "grex 1.4.6\n");
    }

    let output = run(&["-di", "123"], None);
    assert_eq!(expression(&output), "(?i)^\\d\\d\\d$");
}

#[test]
fn default_inference_is_semantically_exact_for_literal_samples() {
    let output = run(&["a", "aa", "aaa"], None);
    assert_eq!(expression(&output), "^a(?:aa?)?$");
    assert_language(expression(&output), &["a", "aa", "aaa"], &["", "aaaa", "b"]);

    let literal = run(&["a.b", "a*b", "a[b", r"a\b"], None);
    assert_language(
        expression(&literal),
        &["a.b", "a*b", "a[b", r"a\b"],
        &["axb", "ab", "aab"],
    );

    let first = run(&["cat", "dog", "cat"], None);
    let reordered = run(&["dog", "cat"], None);
    assert_language(expression(&first), &["cat", "dog"], &["ca", "dogs"]);
    assert_language(expression(&reordered), &["cat", "dog"], &["ca", "dogs"]);
}

#[test]
fn argv_preserves_whitespace_newlines_unicode_and_hyphen_literals() {
    let samples = ["hello world", "tab\there", "line\nbreak", "👨‍👩‍👧‍👦", "-value"];
    let mut arguments = vec!["--"];
    arguments.extend(samples);
    let output = run(&arguments, None);
    assert_language(
        expression(&output),
        &samples,
        &["hello", "linebreak", "value"],
    );

    let unknown = run(&["--bogus"], None);
    assert_eq!(expression(&unknown), r"^\-\-bogus$");
    let after_sample = run(&["foo", "--digits", "--file"], None);
    assert_language(
        expression(&after_sample),
        &["foo", "--digits", "--file"],
        &["123", "digits"],
    );
}

#[test]
fn file_pipe_and_filename_from_stdin_modes_preserve_native_records() {
    let temp = TempDir::new();
    let cases = temp.path().join("cases");
    fs::write(&cases, b"car\r\n\ndog\n").unwrap();

    let output = grex()
        .current_dir(temp.path())
        .args(["--file", "cases"])
        .output()
        .unwrap();
    assert_language(expression(&output), &["car", "dog"], &["", "cat", "dogs"]);

    let piped = run(&["-"], Some(b"car\r\n\ndog\n"));
    assert_language(expression(&piped), &["car", "dog"], &["", "cat", "dogs"]);

    let mut command = grex();
    command
        .current_dir(temp.path())
        .args(["--file", "-"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let mut child = command.spawn().unwrap();
    child.stdin.take().unwrap().write_all(b"  cases\n").unwrap();
    let filename_from_stdin = child.wait_with_output().unwrap();
    assert_language(
        expression(&filename_from_stdin),
        &["car", "dog"],
        &["", "cat", "dogs"],
    );
}

#[test]
fn all_character_generalization_families_and_precedence_are_native() {
    for (option, sample, expected, generalized) in [
        ("--digits", "123", r"^\d\d\d$", "٤٥٦"),
        ("--non-digits", "a!", r"^\D\D$", "é?"),
        ("--spaces", " \t", r"^\s\s$", "\n "),
        ("--non-spaces", "ab", r"^\S\S$", "茶1"),
        ("--words", "a1", r"^\w\w$", "茶_"),
        ("--non-words", "! ", r"^\W\W$", "?\n"),
    ] {
        let output = run(&[option, sample], None);
        assert_eq!(expression(&output), expected);
        assert_language(expression(&output), &[sample, generalized], &[""]);
    }

    let combined = run(&["--digits", "--words", "a1"], None);
    assert_language(expression(&combined), &["a1", "茶٤"], &["!!"]);
}

#[test]
fn repetition_thresholds_and_display_controls_map_directly() {
    let output = run(&["--repetitions", "aa", "bcbc", "defdefdef"], None);
    assert_eq!(expression(&output), "^(?:a{2}|(?:bc){2}|(?:def){3})$");

    let without = run(&["--min-repetitions", "2", "aa"], None);
    let plain = run(&["aa"], None);
    assert_eq!(without.stdout, plain.stdout);
    assert_eq!(
        expression(&run(
            &["--repetitions", "--min-repetitions", "1", "aa"],
            None
        )),
        "^a{2}$"
    );
    assert_eq!(
        expression(&run(
            &["--repetitions", "--min-repetitions", "2", "aa"],
            None
        )),
        "^aa$"
    );
    assert_eq!(
        expression(&run(
            &["--repetitions", "--min-substring-length", "2", "abab"],
            None,
        )),
        "^(?:ab){2}$"
    );

    assert_eq!(
        expression(&run(&["--ignore-case", "Ab", "aB"], None)),
        "(?i)^ab$"
    );
    assert_eq!(
        expression(&run(&["--capture-groups", "ab", "ac"], None)),
        "^a[bc]$"
    );
    assert_eq!(
        expression(&run(&["--no-start-anchor", "a", "aa"], None)),
        "aa?$"
    );
    assert_eq!(
        expression(&run(&["--no-end-anchor", "a", "aa"], None)),
        "^aa?"
    );
    assert_eq!(expression(&run(&["--no-anchors", "a", "aa"], None)), "aa?");

    let verbose = run(&["--verbose", "ab", "ac"], None);
    assert!(text(&verbose.stdout).starts_with("(?x)\n^\n"));
    assert_language(expression(&verbose), &["ab", "ac"], &["a", "ad"]);
}

#[test]
fn escaping_surrogates_color_and_nul_output_remain_native_bytes() {
    assert_eq!(expression(&run(&["--escape", "é"], None)), r"^\u{e9}$");
    assert_eq!(
        expression(&run(&["--escape", "--with-surrogates", "💩"], None)),
        r"^\u{d83d}\u{dca9}$"
    );

    let color = run(&["--colorize", "a", "aa"], None);
    assert_success(&color);
    assert!(color.stdout.contains(&0x1b));

    let nul = run(&["-"], Some(b"a\0b\n"));
    assert_success(&nul);
    assert_eq!(nul.stdout, b"^a\0b$\n");
}

#[test]
fn clap_file_and_native_panic_failures_keep_upstream_statuses() {
    let temp = TempDir::new();
    let cases = temp.path().join("cases");
    fs::write(&cases, b"a\n").unwrap();

    for arguments in [
        &[][..],
        &["--file"],
        &["--with-surrogates", "💩"],
        &["--min-repetitions", "0", "a"],
        &["--min-repetitions", "no", "a"],
        &["--min-repetitions", "4294967296", "a"],
        &["--file", cases.to_str().unwrap(), "a"],
    ] {
        let output = run(arguments, None);
        assert_eq!(output.status.code(), Some(2), "arguments: {arguments:?}");
        assert!(output.stdout.is_empty());
        assert!(!output.stderr.is_empty());
    }

    let missing = temp.path().join("missing");
    let output = run(&["--file", missing.to_str().unwrap()], None);
    assert_eq!(output.status.code(), Some(1));
    assert!(output.stdout.is_empty());
    assert!(!output.stderr.is_empty());

    let invalid = temp.path().join("invalid");
    fs::write(&invalid, [0xff]).unwrap();
    let output = run(&["--file", invalid.to_str().unwrap()], None);
    assert_eq!(output.status.code(), Some(1));
    assert!(output.stdout.is_empty());

    let empty = temp.path().join("empty");
    fs::write(&empty, b"").unwrap();
    let output = run(&["--file", empty.to_str().unwrap()], None);
    assert_eq!(output.status.code(), Some(101));
    assert!(output.stdout.is_empty());
    assert!(text(&output.stderr).contains("panicked"));

    let empty_pipe = run(&["-"], Some(b""));
    assert_eq!(empty_pipe.status.code(), Some(101));
    assert!(empty_pipe.stdout.is_empty());
    let one_empty = run(&["-"], Some(b"\n"));
    assert_eq!(expression(&one_empty), "^$");

    let invalid_pipe = run(&["-"], Some(&[0xff, b'\n']));
    assert_eq!(invalid_pipe.status.code(), Some(101));
    assert!(invalid_pipe.stdout.is_empty());
    assert!(text(&invalid_pipe.stderr).contains("panicked"));
}

#[cfg(unix)]
#[test]
fn unreadable_file_and_closed_pipe_keep_native_failures() {
    let temp = TempDir::new();
    let unreadable = temp.path().join("unreadable");
    fs::write(&unreadable, b"a\n").unwrap();
    fs::set_permissions(&unreadable, fs::Permissions::from_mode(0o000)).unwrap();
    let output = run(&["--file", unreadable.to_str().unwrap()], None);
    fs::set_permissions(&unreadable, fs::Permissions::from_mode(0o600)).unwrap();
    assert_eq!(output.status.code(), Some(1));
    assert!(output.stdout.is_empty());

    let mut child = grex()
        .arg("a")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    drop(child.stdout.take());
    let output = child.wait_with_output().unwrap();
    assert!(!output.status.success());
    assert!(!output.stderr.is_empty());
}

#[test]
fn installer_cached_run_is_quiet_and_test_lookup_rejects_wrong_binaries() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let output = Command::new(root.join("tools/install-grex-rust"))
        .env("CARGO_NET_OFFLINE", "true")
        .output()
        .unwrap();
    assert!(output.status.success(), "stderr: {}", text(&output.stderr));
    assert!(output.stdout.is_empty());
    assert!(output.stderr.is_empty());

    let temp = TempDir::new();
    let missing = temp.path().join("missing");
    assert!(
        validate_grex(&missing)
            .unwrap_err()
            .contains("run ./tools/install-grex-rust")
    );
    let wrong = temp.path().join("grex");
    fs::write(&wrong, b"not an executable").unwrap();
    assert!(
        validate_grex(&wrong)
            .unwrap_err()
            .contains("run ./tools/install-grex-rust")
    );
}

#[cfg(unix)]
#[test]
fn installer_preflights_toolchain_before_project_local_mutation() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let temp = TempDir::new();
    fs::create_dir(temp.path().join("tools")).unwrap();
    fs::copy(
        root.join("tools/install-grex-rust"),
        temp.path().join("tools/install-grex-rust"),
    )
    .unwrap();

    let fake_bin = temp.path().join("fake-bin");
    fs::create_dir(&fake_bin).unwrap();
    let dirname_output = Command::new("sh")
        .args(["-c", "command -v dirname"])
        .output()
        .unwrap();
    assert!(dirname_output.status.success());
    symlink(
        text(&dirname_output.stdout).trim(),
        fake_bin.join("dirname"),
    )
    .unwrap();

    let rustup = fake_bin.join("rustup");
    fs::write(&rustup, b"#!/bin/sh\nexit 1\n").unwrap();
    fs::set_permissions(&rustup, fs::Permissions::from_mode(0o755)).unwrap();
    let cargo = fake_bin.join("cargo");
    fs::write(&cargo, b"#!/bin/sh\ntouch cargo-was-called\nexit 97\n").unwrap();
    fs::set_permissions(&cargo, fs::Permissions::from_mode(0o755)).unwrap();

    let output = Command::new(temp.path().join("tools/install-grex-rust"))
        .current_dir(temp.path())
        .env("PATH", &fake_bin)
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(1));
    assert!(output.stdout.is_empty());
    assert!(text(&output.stderr).contains(
        "rustup toolchain install 1.87.0 --profile minimal --component rustfmt --component clippy"
    ));
    assert!(!temp.path().join(".cargo-home").exists());
    assert!(!temp.path().join("cargo-was-called").exists());
}
