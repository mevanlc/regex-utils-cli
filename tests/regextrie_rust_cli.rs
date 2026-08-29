use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};

#[cfg(unix)]
use std::os::unix::fs::{PermissionsExt, symlink};

static NEXT_TEMP: AtomicU64 = AtomicU64::new(0);

fn binary() -> Command {
    Command::new(env!("CARGO_BIN_EXE_regextrie-rust"))
}

fn run(arguments: &[&str], stdin: Option<&[u8]>) -> Output {
    let mut command = binary();
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
}

struct TempDir(PathBuf);

impl TempDir {
    fn new() -> Self {
        let unique = NEXT_TEMP.fetch_add(1, Ordering::Relaxed);
        let path = std::env::temp_dir().join(format!(
            "regextrie-rust-test-{}-{unique}",
            std::process::id()
        ));
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
fn help_version_and_usage_statuses_are_stable() {
    for arguments in [&["--help"][..], &["matches", "--help"], &["best", "--help"]] {
        let output = run(arguments, None);
        assert_success(&output);
        assert!(text(&output.stdout).contains("Usage:"));
    }

    let output = run(&["--version"], None);
    assert_success(&output);
    assert_eq!(
        text(&output.stdout),
        "regextrie-rust 0.0.0 (regextrie 0.1.0)\n"
    );

    let short = run(&["matches", "foo", "-c", "foo"], None);
    let long = run(&["matches", "foo", "--candidate", "foo"], None);
    assert_success(&short);
    assert_success(&long);
    assert_eq!(short.stdout, long.stdout);

    for arguments in [
        &[][..],
        &["unknown"],
        &["matches", "foo"],
        &["matches", "--scorer", "shortest", "foo", "-c", "foo"],
        &["best", "--scorer", "unknown", "foo", "-c", "foo"],
        &["--version", "matches"],
    ] {
        let output = run(arguments, None);
        assert_eq!(output.status.code(), Some(2), "arguments: {arguments:?}");
        assert!(output.stdout.is_empty());
        assert!(!output.stderr.is_empty());
    }
}

#[test]
fn matches_preserves_upstream_semantics_and_sorts_serialization() {
    let output = run(
        &[
            "matches",
            "a.*",
            "a[0-9]+b.*",
            "a123bbb",
            "-c",
            "a123bbb",
            "-c",
            "xa123bbb",
        ],
        None,
    );
    assert_success(&output);
    assert_eq!(
        text(&output.stdout),
        "{\"candidate\":\"a123bbb\",\"matched\":true,\"matches\":[\"a.*\",\"a123bbb\",\"a[0-9]+b.*\"]}\n\
         {\"candidate\":\"xa123bbb\",\"matched\":false,\"matches\":[]}\n"
    );

    let leftmost_short = run(&["matches", "(a|aaa)", "-c", "aaa"], None);
    assert_success(&leftmost_short);
    assert_eq!(
        text(&leftmost_short.stdout),
        "{\"candidate\":\"aaa\",\"matched\":false,\"matches\":[]}\n"
    );
    let leftmost_long = run(&["matches", "(aaa|a)", "-c", "aaa"], None);
    assert_success(&leftmost_long);
    assert!(text(&leftmost_long.stdout).contains("\"matches\":[\"(aaa|a)\"]"));
}

#[test]
fn duplicates_empty_patterns_unicode_and_classifier_defects_are_visible() {
    let output = run(&["matches", "a.*", "a.*", "abc", "abc", "-c", "abc"], None);
    assert_success(&output);
    assert_eq!(
        text(&output.stdout),
        "{\"candidate\":\"abc\",\"matched\":true,\"matches\":[\"a.*\",\"a.*\",\"abc\"]}\n"
    );

    let zero_patterns = run(&["matches", "-c", ""], Some(b""));
    assert_success(&zero_patterns);
    assert_eq!(
        text(&zero_patterns.stdout),
        "{\"candidate\":\"\",\"matched\":false,\"matches\":[]}\n"
    );
    let empty_pattern = run(&["matches", "-c", ""], Some(b"\n"));
    assert_success(&empty_pattern);
    assert_eq!(
        text(&empty_pattern.stdout),
        "{\"candidate\":\"\",\"matched\":true,\"matches\":[\"\"]}\n"
    );

    let output = run(
        &[
            "matches",
            "^foo$",
            "foo|bar",
            r"\bword\b",
            r"word\s+tail",
            r"\[",
            "茶.*",
            "-c",
            "foo",
            "-c",
            "^foo$",
            "-c",
            "foo|bar",
            "-c",
            "word",
            "-c",
            "word tail",
            "-c",
            "[",
            "-c",
            "茶葉",
        ],
        None,
    );
    assert_success(&output);
    let lines: Vec<&str> = text(&output.stdout).lines().collect();
    assert!(lines[0].contains("\"matched\":false"));
    assert!(lines[1].contains("\"matches\":[\"^foo$\"]"));
    assert!(lines[2].contains("\"matches\":[\"foo|bar\"]"));
    assert!(lines[3].contains("\"matched\":false"));
    assert!(lines[4].contains("\"matched\":false"));
    assert!(lines[5].contains("\"matches\":[\"\\\\[\"]"));
    assert!(lines[6].contains("\"matches\":[\"茶.*\"]"));
}

#[test]
fn best_exposes_all_four_scorers() {
    let patterns = ["best", "a.*", "a[0-9]+b.*", "a123bbb", "-c", "a123bbb"];
    let output = run(&patterns, None);
    assert_success(&output);
    assert_eq!(
        text(&output.stdout),
        "{\"candidate\":\"a123bbb\",\"matched\":true,\"best\":\"a123bbb\",\"scorer\":\"library-default\"}\n"
    );

    for (mode, expected) in [
        ("shortest", "a.*"),
        ("longest", "a[0-9]+b.*"),
        ("input-order", "a.*"),
    ] {
        let output = run(
            &[
                "best",
                "a.*",
                "a[0-9]+b.*",
                "a123bbb",
                "-c",
                "a123bbb",
                "--scorer",
                mode,
            ],
            None,
        );
        assert_success(&output);
        assert!(text(&output.stdout).contains(&format!("\"best\":\"{expected}\"")));
        assert!(text(&output.stdout).contains(&format!("\"scorer\":\"{mode}\"")));
    }

    let no_match = run(&["best", ".*x", "-c", "none"], None);
    assert_success(&no_match);
    assert!(text(&no_match.stdout).contains("\"best\":null"));

    let unicode = run(
        &[
            "best",
            "é.*",
            "é[[:alpha:]]+",
            "-c",
            "éx",
            "--scorer",
            "shortest",
        ],
        None,
    );
    assert_success(&unicode);
    assert!(text(&unicode.stdout).contains("\"best\":\"é.*\""));

    let tied = run(
        &["best", "a.*", "a.+", "-c", "abc", "--scorer", "shortest"],
        None,
    );
    assert_success(&tied);
    assert!(
        text(&tied.stdout).contains("\"best\":\"a.*\"")
            || text(&tied.stdout).contains("\"best\":\"a.+\"")
    );
}

#[test]
fn files_stdin_record_boundaries_controls_and_relative_paths_are_preserved() {
    let temp = TempDir::new();
    fs::write(
        temp.path().join("patterns"),
        b"line\r\nline\x00two\n\n\xe8\x8c\xb6\n",
    )
    .unwrap();
    fs::write(
        temp.path().join("candidates"),
        b"line\nline\x00two\n\n\xe8\x8c\xb6\n",
    )
    .unwrap();
    let mut command = binary();
    let output = command
        .current_dir(temp.path())
        .args([
            "matches",
            "--input",
            "patterns",
            "--candidate-input",
            "candidates",
        ])
        .output()
        .unwrap();
    assert_success(&output);
    let stdout = text(&output.stdout);
    assert_eq!(stdout.lines().count(), 4);
    assert!(stdout.contains("\"candidate\":\"line\\u0000two\""));
    assert!(stdout.contains("\"candidate\":\"茶\""));

    let stdin_candidates = run(
        &[
            "matches",
            "--input",
            temp.path().join("patterns").to_str().unwrap(),
            "-C",
            "-",
        ],
        Some(b"line\r\nmissing\n"),
    );
    assert_success(&stdin_candidates);
    assert_eq!(text(&stdin_candidates.stdout).lines().count(), 2);

    let embedded_lf = run(
        &["matches", "line\nbreak", "--candidate", "line\nbreak"],
        None,
    );
    assert_success(&embedded_lf);
    assert!(text(&embedded_lf.stdout).contains("line\\nbreak"));
}

#[test]
fn data_and_construction_failures_are_atomic() {
    let temp = TempDir::new();
    let empty = temp.path().join("empty");
    let invalid = temp.path().join("invalid");
    fs::write(&empty, b"").unwrap();
    fs::write(&invalid, [0xff]).unwrap();

    let output = run(
        &[
            "matches",
            "foo",
            "--candidate-input",
            empty.to_str().unwrap(),
        ],
        None,
    );
    assert_eq!(output.status.code(), Some(1));
    assert!(output.stdout.is_empty());
    assert_eq!(
        text(&output.stderr),
        "regextrie-rust: candidate input contains no records\n"
    );

    let output = run(
        &["matches", "--input", invalid.to_str().unwrap(), "-c", "foo"],
        None,
    );
    assert_eq!(output.status.code(), Some(1));
    assert!(output.stdout.is_empty());
    assert!(text(&output.stderr).starts_with("regextrie-rust: pattern input is not valid UTF-8:"));

    let output = run(
        &[
            "matches",
            "foo",
            "--candidate-input",
            invalid.to_str().unwrap(),
        ],
        None,
    );
    assert_eq!(output.status.code(), Some(1));
    assert!(output.stdout.is_empty());
    assert!(
        text(&output.stderr).starts_with("regextrie-rust: candidate input is not valid UTF-8:")
    );

    let output = run(&["matches", "[", "good", "-c", "good"], None);
    assert_eq!(output.status.code(), Some(1));
    assert!(output.stdout.is_empty());
    assert!(text(&output.stderr).starts_with("regextrie-rust: failed to build trie:"));

    let output = run(&["matches", "(?=foo)", "-c", "foo"], None);
    assert_eq!(output.status.code(), Some(1));
    assert!(output.stdout.is_empty());

    let missing = temp.path().join("missing");
    let output = run(
        &["matches", "--input", missing.to_str().unwrap(), "-c", "foo"],
        None,
    );
    assert_eq!(output.status.code(), Some(1));
    assert!(output.stdout.is_empty());
    assert!(text(&output.stderr).contains("cannot read pattern input"));
}

#[test]
fn source_arbitration_rejects_mixtures_and_multiple_stdin_consumers() {
    for arguments in [
        &["matches", "foo", "--input", "patterns", "-c", "foo"][..],
        &[
            "matches",
            "foo",
            "-c",
            "foo",
            "--candidate-input",
            "candidates",
        ],
        &["matches", "--input", "-", "--candidate-input", "-"],
        &["matches", "--input", "one", "--input", "two", "-c", "foo"],
        &[
            "matches",
            "foo",
            "--candidate-input",
            "one",
            "--candidate-input",
            "two",
        ],
    ] {
        let output = run(arguments, Some(b"foo\n"));
        assert_eq!(output.status.code(), Some(2), "arguments: {arguments:?}");
        assert!(output.stdout.is_empty());
    }
}

#[test]
fn launcher_works_outside_the_checkout_and_preserves_relative_paths() {
    let temp = TempDir::new();
    fs::write(temp.path().join("patterns"), b"foo\n").unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let output = Command::new(root.join("bin/regextrie-rust"))
        .current_dir(temp.path())
        .args(["matches", "--input", "patterns", "-c", "foo"])
        .env("CARGO_NET_OFFLINE", "true")
        .output()
        .unwrap();
    assert_success(&output);
    assert!(text(&output.stdout).contains("\"matches\":[\"foo\"]"));
}

#[cfg(unix)]
#[test]
fn launcher_reports_missing_cargo_and_forwards_cargo_failures() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let launcher = root.join("bin/regextrie-rust");
    let temp = TempDir::new();
    let dirname_output = Command::new("sh")
        .args(["-c", "command -v dirname"])
        .output()
        .unwrap();
    assert!(dirname_output.status.success());
    let dirname = text(&dirname_output.stdout).trim();
    symlink(dirname, temp.path().join("dirname")).unwrap();

    let output = Command::new(&launcher)
        .env("PATH", temp.path())
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(1));
    assert!(output.stdout.is_empty());
    assert_eq!(
        text(&output.stderr),
        "regextrie-rust: cargo not found on PATH\n"
    );

    let cargo = temp.path().join("cargo");
    fs::write(
        &cargo,
        b"#!/bin/sh\nprintf 'simulated cargo failure\\n' >&2\nexit 37\n",
    )
    .unwrap();
    fs::set_permissions(&cargo, fs::Permissions::from_mode(0o755)).unwrap();
    let output = Command::new(&launcher)
        .env("PATH", temp.path())
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(37));
    assert!(output.stdout.is_empty());
    assert_eq!(text(&output.stderr), "simulated cargo failure\n");
}
