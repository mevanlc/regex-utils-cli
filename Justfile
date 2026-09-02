set minimum-version := "1.55.0"
set positional-arguments

# List the available library recipes
default:
    @just --list

[private]
_perl-deps:
    cpanm --local-lib-contained local --installdeps .

[private]
_perl-clean-deps:
    rm -rf local

[private]
_node-deps:
    npm ci

[private]
_node-clean-deps:
    rm -rf node_modules

[private]
_python-deps:
    uv sync --frozen

[private]
_python-clean-deps:
    rm -rf .venv

[private]
_python-clean-build:
    rm -rf bin/__pycache__ lib/__pycache__ test/__pycache__

[private]
_cargo-deps:
    CARGO_HOME="$PWD/.cargo-home" cargo +1.87.0 fetch --locked
    CARGO_HOME="$PWD/.cargo-home" cargo +1.87.0 metadata --locked --offline --format-version 1 >/dev/null

[private]
_cargo-clean-deps:
    rm -rf .cargo-home

[private]
_cargo-clean-build:
    CARGO_HOME="$PWD/.cargo-home" cargo +1.87.0 clean --manifest-path Cargo.toml

[private]
_native-deps:
    cmake -S . -B build/native -DCMAKE_BUILD_TYPE=Debug -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DREGEX_UTILS_ENABLE_SANITIZERS=OFF -DREGEX_UTILS_BUILD_REGEXTRIE_C=ON -DREGEX_UTILS_BUILD_TRE=ON -DREGEX_UTILS_BUILD_HYPERSCAN=OFF

[private]
_native-clean-tree:
    cmake -E rm -rf "$PWD/build/native"

# Install and verify Regexp::Optimizer dependencies
regexp-optimizer-deps: _perl-deps
    ./bin/regexp-optimizer --version

# Check the Regexp::Optimizer CLI
regexp-optimizer-build:
    PERL5LIB="$PWD/local/lib/perl5" perl -c bin/regexp-optimizer

# Test the Regexp::Optimizer CLI
regexp-optimizer-test:
    prove -v t/regexp-optimizer.t

# Run the Regexp::Optimizer CLI
[no-exit-message]
regexp-optimizer-run *args:
    @exec ./bin/regexp-optimizer "$@"

# Clean shared Perl dependencies
regexp-optimizer-clean-deps: _perl-clean-deps

# Clean Regexp::Optimizer build artifacts (none)
regexp-optimizer-clean-build:
    @:

# Clean Regexp::Optimizer dependencies and build artifacts
regexp-optimizer-clean: regexp-optimizer-clean-build regexp-optimizer-clean-deps

# Install and verify Regexp::Assemble dependencies
regexp-assemble-deps: _perl-deps
    ./bin/regexp-assemble --version

# Check the Regexp::Assemble CLI
regexp-assemble-build:
    PERL5LIB="$PWD/local/lib/perl5" perl -c bin/regexp-assemble

# Test the Regexp::Assemble CLI
regexp-assemble-test:
    prove -v t/regexp-assemble.t

# Run the Regexp::Assemble CLI
[no-exit-message]
regexp-assemble-run *args:
    @exec ./bin/regexp-assemble "$@"

# Clean shared Perl dependencies
regexp-assemble-clean-deps: _perl-clean-deps

# Clean Regexp::Assemble build artifacts (none)
regexp-assemble-clean-build:
    @:

# Clean Regexp::Assemble dependencies and build artifacts
regexp-assemble-clean: regexp-assemble-clean-build regexp-assemble-clean-deps

# Install and verify Regex::PreSuf dependencies
regex-presuf-deps: _perl-deps
    ./bin/regex-presuf --version

# Check the Regex::PreSuf CLI
regex-presuf-build:
    PERL5LIB="$PWD/local/lib/perl5" perl -c bin/regex-presuf

# Test the Regex::PreSuf CLI
regex-presuf-test:
    prove -v t/regex-presuf.t

# Run the Regex::PreSuf CLI
[no-exit-message]
regex-presuf-run *args:
    @exec ./bin/regex-presuf "$@"

# Clean shared Perl dependencies
regex-presuf-clean-deps: _perl-clean-deps

# Clean Regex::PreSuf build artifacts (none)
regex-presuf-clean-build:
    @:

# Clean Regex::PreSuf dependencies and build artifacts
regex-presuf-clean: regex-presuf-clean-build regex-presuf-clean-deps

# Install and verify Regexp::Trie dependencies
regexp-trie-deps: _perl-deps
    ./bin/regexp-trie --version

# Check the Regexp::Trie CLI
regexp-trie-build:
    PERL5LIB="$PWD/local/lib/perl5" perl -c bin/regexp-trie

# Test the Regexp::Trie CLI
regexp-trie-test:
    prove -v t/regexp-trie.t

# Run the Regexp::Trie CLI
[no-exit-message]
regexp-trie-run *args:
    @exec ./bin/regexp-trie "$@"

# Clean shared Perl dependencies
regexp-trie-clean-deps: _perl-clean-deps

# Clean Regexp::Trie build artifacts (none)
regexp-trie-clean-build:
    @:

# Clean Regexp::Trie dependencies and build artifacts
regexp-trie-clean: regexp-trie-clean-build regexp-trie-clean-deps

# Install and verify regexp-tree dependencies
regexp-tree-deps: _node-deps
    npm run --silent regexp-tree -- --version

# Check the regexp-tree CLI
regexp-tree-build:
    node --check node_modules/regexp-tree-cli/bin/regexp-tree-cli

# Test the regexp-tree CLI
regexp-tree-test:
    npm run --silent test:regexp-tree

# Run the regexp-tree CLI
[no-exit-message]
regexp-tree-run *args:
    @exec npm run --silent regexp-tree -- "$@"

# Clean shared Node dependencies
regexp-tree-clean-deps: _node-clean-deps

# Clean regexp-tree build artifacts (none)
regexp-tree-clean-build:
    @:

# Clean regexp-tree dependencies and build artifacts
regexp-tree-clean: regexp-tree-clean-build regexp-tree-clean-deps

# Install and verify oniguruma-parser dependencies
oniguruma-parser-deps: _node-deps
    npm run --silent oniguruma-parser -- --version

# Check the oniguruma-parser CLI
oniguruma-parser-build:
    node --check lib/node-cli.js
    node --check bin/oniguruma-parser

# Test the oniguruma-parser CLI
oniguruma-parser-test:
    npm run --silent test:oniguruma-parser

# Run the oniguruma-parser CLI
[no-exit-message]
oniguruma-parser-run *args:
    @exec npm run --silent oniguruma-parser -- "$@"

# Clean shared Node dependencies
oniguruma-parser-clean-deps: _node-clean-deps

# Clean oniguruma-parser build artifacts (none)
oniguruma-parser-clean-build:
    @:

# Clean oniguruma-parser dependencies and build artifacts
oniguruma-parser-clean: oniguruma-parser-clean-build oniguruma-parser-clean-deps

# Install and verify grex-js dependencies
grex-js-deps: _node-deps
    npm run --silent grex-js -- --version

# Check the grex-js CLI
grex-js-build:
    node --check lib/node-cli.js
    node --check bin/grex-js

# Test the grex-js CLI
grex-js-test:
    npm run --silent test:grex-js

# Run the grex-js CLI
[no-exit-message]
grex-js-run *args:
    @exec npm run --silent grex-js -- "$@"

# Clean shared Node dependencies
grex-js-clean-deps: _node-clean-deps

# Clean grex-js build artifacts (none)
grex-js-clean-build:
    @:

# Clean grex-js dependencies and build artifacts
grex-js-clean: grex-js-clean-build grex-js-clean-deps

# Install and verify regex-trie-js dependencies
regex-trie-js-deps: _node-deps
    npm run --silent regex-trie-js -- --version

# Check the regex-trie-js CLI
regex-trie-js-build:
    node --check lib/node-cli.js
    node --check bin/regex-trie-js

# Test the regex-trie-js CLI
regex-trie-js-test:
    npm run --silent test:regex-trie-js

# Run the regex-trie-js CLI
[no-exit-message]
regex-trie-js-run *args:
    @exec npm run --silent regex-trie-js -- "$@"

# Clean shared Node dependencies
regex-trie-js-clean-deps: _node-clean-deps

# Clean regex-trie-js build artifacts (none)
regex-trie-js-clean-build:
    @:

# Clean regex-trie-js dependencies and build artifacts
regex-trie-js-clean: regex-trie-js-clean-build regex-trie-js-clean-deps

# Install and verify regexfinder dependencies
regexfinder-deps: _python-deps
    uv run --frozen -- ./bin/regexfinder --version

# Compile-check the regexfinder CLI
regexfinder-build:
    uv run --frozen -- python -m py_compile lib/python_cli.py bin/regexfinder

# Test the regexfinder CLI
regexfinder-test:
    uv run --frozen -- python -m unittest test.python_cli_test test.regexfinder_test

# Run the regexfinder CLI
[no-exit-message]
regexfinder-run *args:
    @exec uv run --frozen -- ./bin/regexfinder "$@"

# Clean shared Python dependencies
regexfinder-clean-deps: _python-clean-deps

# Clean shared Python bytecode artifacts
regexfinder-clean-build: _python-clean-build

# Clean regexfinder dependencies and build artifacts
regexfinder-clean: regexfinder-clean-build regexfinder-clean-deps

# Install and verify triegex dependencies
triegex-deps: _python-deps
    uv run --frozen -- ./bin/triegex --version

# Compile-check the triegex CLI
triegex-build:
    uv run --frozen -- python -m py_compile lib/python_cli.py bin/triegex

# Test the triegex CLI
triegex-test:
    uv run --frozen -- python -m unittest test.python_cli_test test.triegex_test

# Run the triegex CLI
[no-exit-message]
triegex-run *args:
    @exec uv run --frozen -- ./bin/triegex "$@"

# Clean shared Python dependencies
triegex-clean-deps: _python-clean-deps

# Clean shared Python bytecode artifacts
triegex-clean-build: _python-clean-build

# Clean triegex dependencies and build artifacts
triegex-clean: triegex-clean-build triegex-clean-deps

# Install and verify retrie dependencies
retrie-deps: _python-deps
    uv run --frozen -- ./bin/retrie --version

# Compile-check the retrie CLI
retrie-build:
    uv run --frozen -- python -m py_compile lib/python_cli.py bin/retrie

# Test the retrie CLI
retrie-test:
    uv run --frozen -- python -m unittest test.python_cli_test test.retrie_test

# Run the retrie CLI
[no-exit-message]
retrie-run *args:
    @exec uv run --frozen -- ./bin/retrie "$@"

# Clean shared Python dependencies
retrie-clean-deps: _python-clean-deps

# Clean shared Python bytecode artifacts
retrie-clean-build: _python-clean-build

# Clean retrie dependencies and build artifacts
retrie-clean: retrie-clean-build retrie-clean-deps

# Install and verify Frak dependencies
frak-deps:
    ./tools/bootstrap-clojure
    CLJ_CONFIG="$PWD/.deps/clj-config" CLJ_CACHE="$PWD/.deps/clj-cache" ./.deps/clojure/bin/clojure -Srepro -P -M:frak
    ./tools/verify-jvm-deps

# Load-check the Frak namespace
frak-build:
    CLJ_CONFIG="$PWD/.deps/clj-config" CLJ_CACHE="$PWD/.deps/clj-cache" ./.deps/clojure/bin/clojure -Srepro -M -e "(require 'frak.cli)"

# Test the Frak CLI
frak-test:
    ./test/frak_cli_test.sh

# Run the Frak CLI
[no-exit-message]
frak-run *args:
    @exec env CLJ_CONFIG="$PWD/.deps/clj-config" CLJ_CACHE="$PWD/.deps/clj-cache" ./.deps/clojure/bin/clojure -Srepro -M:frak "$@"

# Clean Frak dependencies
frak-clean-deps:
    rm -rf .deps

# Clean Frak classpath build caches
frak-clean-build:
    rm -rf .cpcache

# Clean Frak dependencies and build artifacts
frak-clean: frak-clean-build frak-clean-deps

# Fetch and verify regextrie Rust dependencies
regextrie-rust-deps: _cargo-deps

# Build the regextrie Rust CLI
regextrie-rust-build:
    CARGO_HOME="$PWD/.cargo-home" cargo +1.87.0 build --locked --bin regextrie-rust

# Test the regextrie Rust CLI
regextrie-rust-test:
    CARGO_HOME="$PWD/.cargo-home" cargo +1.87.0 nextest run --locked --test regextrie_rust_cli

# Run the regextrie Rust CLI
[no-exit-message]
regextrie-rust-run *args:
    @exec ./bin/regextrie-rust "$@"

# Clean shared Cargo dependencies
regextrie-rust-clean-deps: _cargo-clean-deps

# Clean shared Cargo build artifacts
regextrie-rust-clean-build: _cargo-clean-build

# Clean regextrie Rust dependencies and build artifacts
regextrie-rust-clean: regextrie-rust-clean-build regextrie-rust-clean-deps

# Fetch and verify grex Rust test dependencies
grex-rust-deps: _cargo-deps

# Build and install the project-local grex Rust CLI
grex-rust-build:
    ./tools/install-grex-rust

# Test the grex Rust CLI
grex-rust-test:
    CARGO_HOME="$PWD/.cargo-home" cargo +1.87.0 nextest run --locked --test grex_rust_cli

# Run the grex Rust CLI
[no-exit-message]
grex-rust-run *args:
    @exec ./.cargo-home/bin/grex "$@"

# Clean shared Cargo dependencies
grex-rust-clean-deps: _cargo-clean-deps

# Clean grex Rust and shared Cargo build artifacts
grex-rust-clean-build: _cargo-clean-build
    if [ -x .cargo-home/bin/grex ]; then CARGO_HOME="$PWD/.cargo-home" cargo +1.87.0 uninstall --root "$PWD/.cargo-home" grex; fi

# Clean grex Rust dependencies and build artifacts
grex-rust-clean: grex-rust-clean-build grex-rust-clean-deps

# Configure and verify RegexTrie C dependencies
regextrie-c-deps: _native-deps

# Build the RegexTrie C CLI and library tests
regextrie-c-build:
    cmake --build build/native --parallel --target regextrie-c regextrie-c-library-tests

# Test the RegexTrie C CLI and library
regextrie-c-test:
    ctest --test-dir build/native --output-on-failure -R '^regextrie-c-(library|cli)$'

# Run the RegexTrie C CLI
[no-exit-message]
regextrie-c-run *args:
    @exec ./bin/regextrie-c "$@"

# Clean RegexTrie C dependencies from the shared native tree
regextrie-c-clean-deps: _native-clean-tree

# Clean RegexTrie C build artifacts from the shared native tree
regextrie-c-clean-build: _native-clean-tree

# Clean RegexTrie C dependencies and build artifacts
regextrie-c-clean: regextrie-c-clean-build regextrie-c-clean-deps

# Configure and verify TRE dependencies
tre-deps: _native-deps

# Build the TRE agrep CLI
tre-build:
    cmake --build build/native --parallel --target tre_upstream

# Test the TRE agrep CLI
tre-test:
    ctest --test-dir build/native --output-on-failure -R '^tre-agrep-cli$'

# Run the TRE agrep CLI
[no-exit-message]
tre-run *args:
    @exec build/native/tre-install/bin/agrep "$@"

# Clean TRE dependencies from the shared native tree
tre-clean-deps: _native-clean-tree

# Clean TRE build artifacts from the shared native tree
tre-clean-build: _native-clean-tree

# Clean TRE dependencies and build artifacts
tre-clean: tre-clean-build tre-clean-deps

# Install and verify Hyperscan's locked Conan dependency graph
hyperscan-deps:
    CONAN_HOME="$PWD/.conan2" uvx --from conan==2.31.2 conan profile detect --force
    CONAN_HOME="$PWD/.conan2" uvx --from conan==2.31.2 conan create conan/recipes/hyperscan --profile:host=conan/profiles/hyperscan-x86_64 --profile:build=default --lockfile=conan.lock --build=missing
    CONAN_HOME="$PWD/.conan2" uvx --from conan==2.31.2 conan install . --profile:host=conan/profiles/hyperscan-x86_64 --profile:build=default --lockfile=conan.lock --build=missing

# Build the Hyperscan CLI
hyperscan-build:
    cmake -S . -B build/hyperscan -DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE=build/hyperscan/conan/conan_toolchain.cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DREGEX_UTILS_ENABLE_SANITIZERS=OFF -DREGEX_UTILS_BUILD_REGEXTRIE_C=OFF -DREGEX_UTILS_BUILD_TRE=OFF -DREGEX_UTILS_BUILD_HYPERSCAN=ON
    cmake --build build/hyperscan --parallel

# Test the Hyperscan CLI
hyperscan-test:
    ctest --test-dir build/hyperscan --output-on-failure -R '^hyperscan-cli$'

# Run the Hyperscan CLI
[no-exit-message]
hyperscan-run *args:
    @exec ./bin/hyperscan "$@"

# Clean Hyperscan's Conan dependency artifacts and cache
hyperscan-clean-deps:
    cmake -E rm -rf "$PWD/.conan2" "$PWD/build/hyperscan/conan" "$PWD/conan/recipes/hyperscan/test_package/build" "$PWD/conan/recipes/hyperscan/test_package/CMakeUserPresets.json" "$PWD/CMakeUserPresets.json"

# Clean the Hyperscan consumer build artifacts
hyperscan-clean-build:
    if [ -f build/hyperscan/CMakeCache.txt ]; then cmake --build build/hyperscan --target clean; fi

# Clean Hyperscan dependencies and build artifacts
hyperscan-clean: hyperscan-clean-build hyperscan-clean-deps
    cmake -E rm -rf "$PWD/build/hyperscan"
