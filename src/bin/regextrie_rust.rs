use std::collections::HashMap;
use std::fs;
use std::io::{self, IsTerminal, Read, Write};
use std::path::Path;
use std::process::ExitCode;

use clap::{Args, Parser, Subcommand, ValueEnum};
use regextrie::RegexTrie;
use serde::Serialize;

const PROGRAM: &str = "regextrie-rust";
const VERSION: &str = "regextrie-rust 0.0.0 (regextrie 0.1.0)\n";

#[derive(Debug, Parser)]
#[command(
    name = "regextrie-rust",
    about = "Exercise regextrie matching and best-match selection",
    disable_version_flag = true
)]
struct Cli {
    /// Print CLI and dependency versions
    #[arg(short = 'V', long)]
    version: bool,

    #[command(subcommand)]
    command: Option<Command>,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// Return all upstream matches for each candidate
    Matches(CommonArgs),
    /// Return the upstream best match for each candidate
    Best(BestArgs),
}

#[derive(Debug, Args)]
struct CommonArgs {
    /// Regex/plain patterns as separate arguments
    #[arg(value_name = "PATTERN", conflicts_with = "input")]
    patterns: Vec<String>,

    /// Read LF/CRLF-delimited patterns; use - for stdin
    #[arg(short = 'i', long, value_name = "FILE")]
    input: Option<String>,

    /// Candidate string; repeatable
    #[arg(
        short = 'c',
        long = "candidate",
        value_name = "TEXT",
        action = clap::ArgAction::Append,
        conflicts_with = "candidate_input"
    )]
    candidates: Vec<String>,

    /// Read LF/CRLF-delimited candidates; use - for stdin
    #[arg(short = 'C', long, value_name = "FILE")]
    candidate_input: Option<String>,
}

#[derive(Debug, Args)]
struct BestArgs {
    #[command(flatten)]
    common: CommonArgs,

    /// Select the best-match scoring policy
    #[arg(
        short,
        long,
        value_enum,
        default_value_t = Scorer::LibraryDefault,
        value_name = "MODE"
    )]
    scorer: Scorer,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, ValueEnum)]
#[value(rename_all = "kebab-case")]
enum Scorer {
    LibraryDefault,
    Shortest,
    Longest,
    InputOrder,
}

impl Scorer {
    fn name(self) -> &'static str {
        match self {
            Self::LibraryDefault => "library-default",
            Self::Shortest => "shortest",
            Self::Longest => "longest",
            Self::InputOrder => "input-order",
        }
    }
}

#[derive(Debug)]
struct CliError {
    status: u8,
    message: String,
}

impl CliError {
    fn usage(message: impl Into<String>) -> Self {
        Self {
            status: 2,
            message: message.into(),
        }
    }

    fn processing(message: impl Into<String>) -> Self {
        Self {
            status: 1,
            message: message.into(),
        }
    }
}

#[derive(Serialize)]
struct MatchesOutput<'a> {
    candidate: &'a str,
    matched: bool,
    matches: Vec<String>,
}

#[derive(Serialize)]
struct BestOutput<'a> {
    candidate: &'a str,
    matched: bool,
    best: Option<String>,
    scorer: &'static str,
}

fn split_records(text: &str) -> Vec<String> {
    if text.is_empty() {
        return Vec::new();
    }

    let terminated = text.ends_with('\n');
    let mut pieces: Vec<&str> = text.split('\n').collect();
    if terminated {
        pieces.pop();
    }
    let last = pieces.len().saturating_sub(1);

    pieces
        .into_iter()
        .enumerate()
        .map(|(index, piece)| {
            let precedes_lf = terminated || index < last;
            if precedes_lf {
                piece.strip_suffix('\r').unwrap_or(piece).to_owned()
            } else {
                piece.to_owned()
            }
        })
        .collect()
}

fn decode_records(bytes: Vec<u8>, description: &str) -> Result<Vec<String>, CliError> {
    let text = String::from_utf8(bytes).map_err(|error| {
        CliError::processing(format!("{description} is not valid UTF-8: {error}"))
    })?;
    Ok(split_records(&text))
}

fn read_file_records(path: &str, description: &str) -> Result<Vec<String>, CliError> {
    let bytes = fs::read(Path::new(path)).map_err(|error| {
        CliError::processing(format!("cannot read {description} {path:?}: {error}"))
    })?;
    decode_records(bytes, description)
}

fn read_stdin_records(description: &str) -> Result<Vec<String>, CliError> {
    let mut bytes = Vec::new();
    io::stdin()
        .read_to_end(&mut bytes)
        .map_err(|error| CliError::processing(format!("cannot read {description}: {error}")))?;
    decode_records(bytes, description)
}

fn load_inputs(common: CommonArgs) -> Result<(Vec<String>, Vec<String>), CliError> {
    let patterns_use_stdin =
        common.patterns.is_empty() && common.input.as_deref().is_none_or(|path| path == "-");
    let candidates_use_stdin = common.candidate_input.as_deref() == Some("-");

    if patterns_use_stdin && candidates_use_stdin {
        return Err(CliError::usage(
            "pattern and candidate input cannot both read stdin",
        ));
    }

    if common.candidates.is_empty() && common.candidate_input.is_none() {
        return Err(CliError::usage(
            "provide candidates with --candidate or --candidate-input",
        ));
    }

    let patterns = if !common.patterns.is_empty() {
        common.patterns
    } else if let Some(path) = common.input {
        if path == "-" {
            read_stdin_records("pattern input")?
        } else {
            read_file_records(&path, "pattern input")?
        }
    } else {
        if io::stdin().is_terminal() {
            return Err(CliError::usage(
                "provide patterns as arguments, with --input, or on stdin",
            ));
        }
        read_stdin_records("pattern input")?
    };

    let candidates = if !common.candidates.is_empty() {
        common.candidates
    } else {
        let path = common
            .candidate_input
            .expect("candidate source was validated");
        let records = if path == "-" {
            read_stdin_records("candidate input")?
        } else {
            read_file_records(&path, "candidate input")?
        };
        if records.is_empty() {
            return Err(CliError::processing("candidate input contains no records"));
        }
        records
    };

    Ok((patterns, candidates))
}

fn build_trie(patterns: &[String], scorer: Scorer) -> Result<RegexTrie, CliError> {
    let result = match scorer {
        Scorer::LibraryDefault => RegexTrie::from(patterns),
        Scorer::Shortest => {
            RegexTrie::from_with_scorer(patterns, Box::new(|pattern, _| pattern.len()))
        }
        Scorer::Longest => {
            RegexTrie::from_with_scorer(patterns, Box::new(|pattern, _| usize::MAX - pattern.len()))
        }
        Scorer::InputOrder => {
            let mut positions = HashMap::new();
            for (index, pattern) in patterns.iter().enumerate() {
                positions.entry(pattern.clone()).or_insert(index);
            }
            RegexTrie::from_with_scorer(
                patterns,
                Box::new(move |pattern, _| positions.get(pattern).copied().unwrap_or(usize::MAX)),
            )
        }
    };

    result.map_err(|error| CliError::processing(format!("failed to build trie: {error}")))
}

fn serialize_line<T: Serialize>(value: &T, output: &mut Vec<u8>) -> Result<(), CliError> {
    serde_json::to_writer(&mut *output, value)
        .map_err(|error| CliError::processing(format!("cannot serialize output: {error}")))?;
    output.push(b'\n');
    Ok(())
}

fn run_matches(common: CommonArgs) -> Result<Vec<u8>, CliError> {
    let (patterns, candidates) = load_inputs(common)?;
    let trie = build_trie(&patterns, Scorer::LibraryDefault)?;
    let mut output = Vec::new();

    for candidate in &candidates {
        let mut matches = trie.find_matches(candidate);
        matches.sort();
        serialize_line(
            &MatchesOutput {
                candidate,
                matched: !matches.is_empty(),
                matches,
            },
            &mut output,
        )?;
    }
    Ok(output)
}

fn run_best(args: BestArgs) -> Result<Vec<u8>, CliError> {
    let scorer = args.scorer;
    let (patterns, candidates) = load_inputs(args.common)?;
    let trie = build_trie(&patterns, scorer)?;
    let mut output = Vec::new();

    for candidate in &candidates {
        let best = trie.find_best_match(candidate);
        serialize_line(
            &BestOutput {
                candidate,
                matched: best.is_some(),
                best,
                scorer: scorer.name(),
            },
            &mut output,
        )?;
    }
    Ok(output)
}

fn execute(cli: Cli) -> Result<Vec<u8>, CliError> {
    if cli.version {
        if cli.command.is_some() {
            return Err(CliError::usage("--version does not accept a subcommand"));
        }
        return Ok(VERSION.as_bytes().to_vec());
    }

    match cli.command {
        Some(Command::Matches(args)) => run_matches(args),
        Some(Command::Best(args)) => run_best(args),
        None => Err(CliError::usage("a subcommand is required: matches or best")),
    }
}

fn write_output<W: Write>(writer: &mut W, output: &[u8]) -> Result<(), CliError> {
    match writer.write_all(output) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == io::ErrorKind::BrokenPipe => Ok(()),
        Err(error) => Err(CliError::processing(format!(
            "cannot write stdout: {error}"
        ))),
    }
}

fn report(error: CliError) -> ExitCode {
    eprintln!("{PROGRAM}: {}", error.message);
    ExitCode::from(error.status)
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    let output = match execute(cli) {
        Ok(output) => output,
        Err(error) => return report(error),
    };

    match write_output(&mut io::stdout().lock(), &output) {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => report(error),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct FailingWriter(io::ErrorKind);

    impl Write for FailingWriter {
        fn write(&mut self, _buffer: &[u8]) -> io::Result<usize> {
            Err(io::Error::from(self.0))
        }

        fn flush(&mut self) -> io::Result<()> {
            Ok(())
        }
    }

    #[test]
    fn record_splitting_preserves_delimiter_contract() {
        assert_eq!(split_records(""), Vec::<String>::new());
        assert_eq!(split_records("a\n"), ["a"]);
        assert_eq!(split_records("a\n\n"), ["a", ""]);
        assert_eq!(split_records("\n"), [""]);
        assert_eq!(split_records("a\r\nb\rc"), ["a", "b\rc"]);
        assert_eq!(split_records("a\r"), ["a\r"]);
    }

    #[test]
    fn broken_pipe_is_success_and_other_write_errors_are_failures() {
        assert!(write_output(&mut FailingWriter(io::ErrorKind::BrokenPipe), b"x").is_ok());
        let error = write_output(&mut FailingWriter(io::ErrorKind::Other), b"x").unwrap_err();
        assert_eq!(error.status, 1);
        assert!(error.message.starts_with("cannot write stdout:"));
    }
}
