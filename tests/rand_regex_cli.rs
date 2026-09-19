use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};

use regex::Regex;
use serde_json::Value;

#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;

static NEXT_TEMP: AtomicU64 = AtomicU64::new(0);

fn binary() -> Command {
    Command::new(env!("CARGO_BIN_EXE_rand-regex"))
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
        let path =
            std::env::temp_dir().join(format!("rand-regex-test-{}-{unique}", std::process::id()));
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
fn help_version_and_clap_usage_are_stable() {
    let help = run(&["--help"], None);
    assert_success(&help);
    assert!(text(&help.stdout).contains("Generate random strings or byte strings"));
    assert!(text(&help.stdout).contains("--max-repeat"));
    assert!(text(&help.stdout).contains("--bytes"));

    let version = run(&["--version"], None);
    assert_success(&version);
    assert_eq!(
        text(&version.stdout),
        "rand-regex 0.0.0 (rand_regex 0.19.0)\n"
    );

    for arguments in [
        &["--bogus", "a"][..],
        &["a", "b"],
        &["--ascii", "--bytes", "a"],
        &["--bytes", "--jsonl", "a"],
        &["--version", "a"],
    ] {
        let output = run(arguments, None);
        assert_eq!(output.status.code(), Some(2), "arguments: {arguments:?}");
        assert!(output.stdout.is_empty());
        assert!(!output.stderr.is_empty());
    }
}

#[test]
fn seeded_generation_is_reproducible_and_counted() {
    let arguments = [
        "--seed",
        "42",
        "--count",
        "3",
        "--max-repeat",
        "4",
        "[a-c]{1,3}",
    ];
    let first = run(&arguments, None);
    let second = run(&arguments, None);
    assert_success(&first);
    assert_success(&second);
    assert_eq!(first.stdout, second.stdout);
    assert_eq!(text(&first.stdout), "b\nb\nbcb\n");

    let zero = run(&["--count", "0", "[a-c]"], None);
    assert_success(&zero);
    assert!(zero.stdout.is_empty());
}

#[test]
fn every_generated_value_matches_the_supplied_rust_regex() {
    let output = run(
        &[
            "--seed",
            "90210",
            "--count",
            "100",
            "--max-repeat",
            "5",
            r"(?:foo|bar)-[[:alpha:]]{1,3}-\d+",
        ],
        None,
    );
    assert_success(&output);
    let matcher = Regex::new(r"^(?:foo|bar)-[[:alpha:]]{1,3}-\d+$").unwrap();
    let values: Vec<_> = text(&output.stdout).lines().collect();
    assert_eq!(values.len(), 100);
    assert!(values.iter().all(|value| matcher.is_match(value)));
}

#[test]
fn ascii_jsonl_and_open_repeat_controls_map_to_upstream_parsing() {
    let output = run(
        &[
            "--seed", "42", "--count", "3", "--ascii", "--jsonl", r"\d{2}",
        ],
        None,
    );
    assert_success(&output);
    assert_eq!(
        text(&output.stdout),
        "{\"value\":\"15\"}\n{\"value\":\"25\"}\n{\"value\":\"86\"}\n"
    );
    for line in text(&output.stdout).lines() {
        let object: Value = serde_json::from_str(line).unwrap();
        assert!(object["value"].as_str().unwrap().is_ascii());
    }

    let bounded = run(
        &["--seed", "1", "--count", "3", "--max-repeat", "0", "a+"],
        None,
    );
    assert_success(&bounded);
    assert_eq!(text(&bounded.stdout), "a\na\na\n");

    let controls = run(&["--seed", "1", "--jsonl", r"a\nb"], None);
    assert_success(&controls);
    assert_eq!(text(&controls.stdout), "{\"value\":\"a\\nb\"}\n");
}

#[test]
fn byte_mode_preserves_non_utf8_values_as_hex() {
    let output = run(
        &["--seed", "42", "--count", "3", "--bytes", r"[\x80-\xff]{2}"],
        None,
    );
    assert_success(&output);
    assert_eq!(text(&output.stdout), "91c3\n9fc5\nefd1\n");
}

#[test]
fn complete_pattern_files_and_stdin_are_supported() {
    let temp = TempDir::new();
    let pattern = temp.path().join("pattern");
    fs::write(&pattern, r"[ab]{2}").unwrap();

    let from_file = run(
        &[
            "--seed",
            "7",
            "--count",
            "4",
            "--input",
            pattern.to_str().unwrap(),
        ],
        None,
    );
    let from_stdin = run(
        &["--seed", "7", "--count", "4", "--input", "-"],
        Some(br"[ab]{2}"),
    );
    let implicit = run(&["--seed", "7", "--count", "4"], Some(br"[ab]{2}"));
    assert_success(&from_file);
    assert_success(&from_stdin);
    assert_success(&implicit);
    assert_eq!(from_file.stdout, from_stdin.stdout);
    assert_eq!(from_file.stdout, implicit.stdout);
}

#[test]
fn invalid_utf8_syntax_anchors_and_unsatisfiable_patterns_are_failures() {
    let temp = TempDir::new();
    let invalid_utf8 = temp.path().join("invalid");
    fs::write(&invalid_utf8, [0xff]).unwrap();

    for (arguments, diagnostic) in [
        (
            vec!["--input", invalid_utf8.to_str().unwrap()],
            "pattern input is not valid UTF-8",
        ),
        (vec!["("], "cannot build generator:"),
        (vec!["^foo$"], "anchor is not supported"),
        (vec!["[a&&b]"], "regex is unsatisfiable"),
    ] {
        let output = run(&arguments, None);
        assert_eq!(output.status.code(), Some(1), "arguments: {arguments:?}");
        assert!(output.stdout.is_empty());
        assert!(
            text(&output.stderr).contains(diagnostic),
            "stderr: {}",
            text(&output.stderr)
        );
    }
}

#[test]
fn launcher_works_outside_checkout_and_reports_missing_cargo() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let temp = TempDir::new();
    let output = Command::new(root.join("bin/rand-regex"))
        .args(["--seed", "42", "[ab]"])
        .current_dir(temp.path())
        .stdin(Stdio::null())
        .output()
        .unwrap();
    assert_success(&output);
    assert_eq!(text(&output.stdout), "a\n");

    let fixture = temp.path().join("fixture");
    fs::create_dir(&fixture).unwrap();
    let launcher = fixture.join("rand-regex");
    fs::copy(root.join("bin/rand-regex"), &launcher).unwrap();
    #[cfg(unix)]
    fs::set_permissions(&launcher, fs::Permissions::from_mode(0o755)).unwrap();
    let missing = Command::new(&launcher)
        .arg("--help")
        .env("PATH", "/usr/bin:/bin")
        .stdin(Stdio::null())
        .output()
        .unwrap();
    assert_eq!(missing.status.code(), Some(1));
    assert!(missing.stdout.is_empty());
    assert_eq!(
        text(&missing.stderr),
        "rand-regex: cargo not found on PATH\n"
    );
}
