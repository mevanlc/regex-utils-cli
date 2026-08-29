"""Shared process, input, and argument helpers for the Python exercise CLIs."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import NoReturn


class CliError(Exception):
    def __init__(self, status: int, message: str, *, usage_hint: bool = False) -> None:
        super().__init__(message)
        self.status = status
        self.usage_hint = usage_hint


class CliExit(Exception):
    def __init__(self, status: int = 0) -> None:
        self.status = status


def usage_error(message: object) -> NoReturn:
    raise CliError(2, clean_message(message), usage_hint=True)


def runtime_error(message: object) -> NoReturn:
    raise CliError(1, clean_message(message))


def clean_message(message: object) -> str:
    cleaned = " ".join(str(message or "unknown failure").splitlines()).strip()
    return cleaned or "unknown failure"


class StrictArgumentParser(argparse.ArgumentParser):
    def __init__(self, **kwargs: object) -> None:
        super().__init__(add_help=False, **kwargs)

    def error(self, message: str) -> NoReturn:
        usage_error(message)


class StoreOnce(argparse.Action):
    def __call__(
        self,
        parser: argparse.ArgumentParser,
        namespace: argparse.Namespace,
        values: object,
        option_string: str | None = None,
    ) -> None:
        marker = f"_seen_{self.dest}"
        if getattr(namespace, marker, False):
            raise argparse.ArgumentError(self, f"{option_string} may be supplied only once")
        setattr(namespace, marker, True)
        setattr(namespace, self.dest, values)


class StoreTrueOnce(StoreOnce):
    def __init__(self, option_strings: list[str], dest: str, **kwargs: object) -> None:
        super().__init__(option_strings, dest, nargs=0, **kwargs)

    def __call__(
        self,
        parser: argparse.ArgumentParser,
        namespace: argparse.Namespace,
        values: object,
        option_string: str | None = None,
    ) -> None:
        super().__call__(parser, namespace, True, option_string)


def decode_utf8(data: bytes, source: str) -> str:
    try:
        return data.decode("utf-8", errors="strict")
    except UnicodeDecodeError as error:
        runtime_error(f"{source} is not valid UTF-8: {error}")


def read_bytes(pathname: str, label: str) -> bytes:
    try:
        if pathname == "-":
            return sys.stdin.buffer.read()
        return Path(pathname).read_bytes()
    except (OSError, ValueError) as error:
        runtime_error(f"cannot read {label}: {error}")


def read_text(pathname: str, label: str) -> str:
    return decode_utf8(read_bytes(pathname, label), label)


def split_records(text: str) -> list[str]:
    if not text:
        return []
    records = text.split("\n")
    ends_with_lf = text.endswith("\n")
    if ends_with_lf:
        records.pop()
    delimited_count = len(records) if ends_with_lf else max(0, len(records) - 1)
    for index in range(delimited_count):
        if records[index].endswith("\r"):
            records[index] = records[index][:-1]
    return records


def read_records(pathname: str, label: str) -> list[str]:
    return split_records(read_text(pathname, label))


def stdin_is_terminal() -> bool:
    return sys.stdin.isatty()


def compact_json(value: object) -> str:
    return json.dumps(
        value,
        ensure_ascii=False,
        separators=(",", ":"),
        allow_nan=False,
    )


def write_stdout(output: str) -> None:
    try:
        data = output.encode("utf-8", errors="strict")
        os.write(sys.stdout.fileno(), data)
    except BrokenPipeError:
        try:
            devnull = os.open(os.devnull, os.O_WRONLY)
            os.dup2(devnull, sys.stdout.fileno())
            os.close(devnull)
        except OSError:
            pass
    except (OSError, UnicodeError, ValueError) as error:
        runtime_error(f"cannot write stdout: {error}")


def run_cli(program: str, main: object) -> int:
    try:
        main()
        return 0
    except CliExit as error:
        return error.status
    except CliError as error:
        sys.stderr.write(f"{program}: {clean_message(error)}\n")
        if error.usage_hint:
            sys.stderr.write(f"Try '{program} --help' for usage.\n")
        return error.status
    except Exception as error:  # Defensive process boundary; never expose tracebacks.
        sys.stderr.write(f"{program}: {clean_message(error)}\n")
        return 1
