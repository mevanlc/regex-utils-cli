#include <hs/hs.h>

#include <cerrno>
#include <climits>
#include <csignal>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <memory>
#include <new>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#ifndef REGEX_UTILS_HYPERSCAN_PACKAGE_SANITIZERS
#error "the Hyperscan package must declare its sanitizer mode"
#endif

#if REGEX_UTILS_HYPERSCAN_PACKAGE_SANITIZERS != REGEX_UTILS_HYPERSCAN_EXPECT_SANITIZERS
#error "the consumer and Hyperscan package sanitizer modes do not match"
#endif

namespace {

const std::size_t kMaxPatterns = 10000;
const std::size_t kMaxPatternBytes = 8192;
const std::size_t kMaxExpressionBytes = 8U * 1024U * 1024U;
const std::size_t kMaxExpressionFileBytes =
    kMaxExpressionBytes + (2U * kMaxPatterns);
const std::size_t kMaxSubjectBytes = 256U * 1024U * 1024U;
const std::uint64_t kDefaultChunkSize = 4096;
const std::uint64_t kDefaultMaxMatches = 100000;
const std::uint64_t kMaxMatchesLimit = 1000000;

class CliError : public std::runtime_error {
  public:
    CliError(int status, const std::string &message)
        : std::runtime_error(message), status_(status) {}

    int status() const { return status_; }

  private:
    int status_;
};

class UsageError : public CliError {
  public:
    explicit UsageError(const std::string &message) : CliError(2, message) {}
};

class RuntimeError : public CliError {
  public:
    explicit RuntimeError(const std::string &message) : CliError(1, message) {}
};

enum class Command { Scan, Info };
enum class Mode { Block, Stream, Vectored };
enum class Horizon { Small, Medium, Large };

struct Config {
    Command command;
    Mode mode;
    Horizon horizon;
    std::vector<std::string> expressions;
    std::string expression_file;
    std::string input_path;
    std::string text;
    std::uint64_t chunk_size;
    std::uint64_t max_matches;
    std::uint64_t min_offset;
    std::uint64_t max_offset;
    std::uint64_t min_length;
    std::uint32_t edit_distance;
    std::uint32_t hamming_distance;
    bool expression_file_seen;
    bool input_seen;
    bool text_seen;
    bool mode_seen;
    bool horizon_seen;
    bool chunk_size_seen;
    bool max_matches_seen;
    bool min_offset_seen;
    bool max_offset_seen;
    bool min_length_seen;
    bool edit_distance_seen;
    bool hamming_distance_seen;
    bool literal;
    bool caseless;
    bool dotall;
    bool multiline;
    bool single_match;
    bool allow_empty;
    bool utf8;
    bool ucp;
    bool prefilter;
    bool som_leftmost;

    explicit Config(Command selected)
        : command(selected), mode(Mode::Block), horizon(Horizon::Large),
          chunk_size(kDefaultChunkSize), max_matches(kDefaultMaxMatches),
          min_offset(0), max_offset(0), min_length(0), edit_distance(0),
          hamming_distance(0), expression_file_seen(false), input_seen(false),
          text_seen(false), mode_seen(false), horizon_seen(false),
          chunk_size_seen(false), max_matches_seen(false),
          min_offset_seen(false), max_offset_seen(false), min_length_seen(false),
          edit_distance_seen(false), hamming_distance_seen(false), literal(false),
          caseless(false), dotall(false), multiline(false), single_match(false),
          allow_empty(false), utf8(false), ucp(false), prefilter(false),
          som_leftmost(false) {}
};

struct DatabaseDeleter {
    void operator()(hs_database_t *database) const {
        if (database != NULL) {
            (void)hs_free_database(database);
        }
    }
};

struct ScratchDeleter {
    void operator()(hs_scratch_t *scratch) const {
        if (scratch != NULL) {
            (void)hs_free_scratch(scratch);
        }
    }
};

typedef std::unique_ptr<hs_database_t, DatabaseDeleter> DatabasePtr;
typedef std::unique_ptr<hs_scratch_t, ScratchDeleter> ScratchPtr;

const char kHelp[] =
    "Usage:\n"
    "  hyperscan scan [PATTERN_OPTIONS] [SCAN_OPTIONS]\n"
    "  hyperscan info [PATTERN_OPTIONS]\n"
    "  hyperscan --help\n"
    "  hyperscan --version\n"
    "\n"
    "Pattern source (choose one):\n"
    "  -e, --expression PATTERN       Add one pattern; repeatable\n"
    "  -f, --expression-file FILE     Read LF-delimited patterns from FILE\n"
    "\n"
    "Compilation:\n"
    "      --literal                  Compile byte literals instead of regexes\n"
    "      --mode MODE                block, stream, or vectored [default: block]\n"
    "  -i, --caseless                 Case-insensitive matching\n"
    "  -s, --dotall                   Make dot match newlines\n"
    "  -m, --multiline                Enable multiline anchors\n"
    "      --single-match             Report at most one match per pattern\n"
    "      --allow-empty              Permit regexes that match empty input\n"
    "      --utf8                     Enable strict UTF-8 mode\n"
    "      --ucp                      Enable Unicode properties; requires --utf8\n"
    "      --prefilter                Permit false-positive prefilter matches\n"
    "      --som-leftmost             Report leftmost start offsets\n"
    "      --som-horizon HORIZON      small, medium, or large for stream SOM\n"
    "      --min-offset N             Minimum match end offset\n"
    "      --max-offset N             Maximum match end offset\n"
    "      --min-length N             Minimum match length\n"
    "      --edit-distance N          Experimental edit distance\n"
    "      --hamming-distance N       Experimental Hamming distance\n"
    "\n"
    "Scan input:\n"
    "      --input FILE               Read binary subject; - is stdin [default]\n"
    "      --text TEXT                Use exact argument bytes as the subject\n"
    "      --chunk-size N             Stream/vector chunk bytes [default: 4096]\n"
    "      --max-matches N            Event limit [default: 100000]\n";

void mark_once(bool &seen, const char *option) {
    if (seen) {
        throw UsageError(std::string("option repeated: ") + option);
    }
    seen = true;
}

void set_boolean(bool &value, const char *option) {
    if (value) {
        throw UsageError(std::string("option repeated: ") + option);
    }
    value = true;
}

const char *take_value(int argc, char **argv, int &index, const char *option) {
    if (index + 1 >= argc) {
        throw UsageError(std::string("missing value for ") + option);
    }
    ++index;
    return argv[index];
}

std::uint64_t parse_decimal(const std::string &value, const char *option,
                            std::uint64_t maximum, bool positive) {
    if (value.empty()) {
        throw UsageError(std::string("invalid decimal value for ") + option);
    }
    std::uint64_t result = 0;
    for (std::size_t i = 0; i < value.size(); ++i) {
        const unsigned char byte = static_cast<unsigned char>(value[i]);
        if (byte < '0' || byte > '9') {
            throw UsageError(std::string("invalid decimal value for ") + option);
        }
        const std::uint64_t digit = static_cast<std::uint64_t>(byte - '0');
        if (result > (maximum - digit) / 10U) {
            throw UsageError(std::string("decimal value out of range for ") + option);
        }
        result = (result * 10U) + digit;
    }
    if (positive && result == 0) {
        throw UsageError(std::string(option) + " must be positive");
    }
    return result;
}

Mode parse_mode(const std::string &value) {
    if (value == "block") {
        return Mode::Block;
    }
    if (value == "stream") {
        return Mode::Stream;
    }
    if (value == "vectored") {
        return Mode::Vectored;
    }
    throw UsageError("--mode must be block, stream, or vectored");
}

Horizon parse_horizon(const std::string &value) {
    if (value == "small") {
        return Horizon::Small;
    }
    if (value == "medium") {
        return Horizon::Medium;
    }
    if (value == "large") {
        return Horizon::Large;
    }
    throw UsageError("--som-horizon must be small, medium, or large");
}

Config parse_arguments(int argc, char **argv) {
    if (argc < 2) {
        throw UsageError("a scan or info command is required");
    }
    const std::string command(argv[1]);
    Config config(command == "scan" ? Command::Scan : Command::Info);
    if (command != "scan" && command != "info") {
        throw UsageError("a scan or info command is required");
    }

    for (int i = 2; i < argc; ++i) {
        const std::string option(argv[i]);
        if (option == "-e" || option == "--expression") {
            config.expressions.push_back(take_value(argc, argv, i, option.c_str()));
        } else if (option == "-f" || option == "--expression-file") {
            mark_once(config.expression_file_seen, "--expression-file");
            config.expression_file = take_value(argc, argv, i, option.c_str());
        } else if (option == "--input") {
            mark_once(config.input_seen, "--input");
            config.input_path = take_value(argc, argv, i, "--input");
        } else if (option == "--text") {
            mark_once(config.text_seen, "--text");
            config.text = take_value(argc, argv, i, "--text");
        } else if (option == "--mode") {
            mark_once(config.mode_seen, "--mode");
            config.mode = parse_mode(take_value(argc, argv, i, "--mode"));
        } else if (option == "--som-horizon") {
            mark_once(config.horizon_seen, "--som-horizon");
            config.horizon =
                parse_horizon(take_value(argc, argv, i, "--som-horizon"));
        } else if (option == "--chunk-size") {
            mark_once(config.chunk_size_seen, "--chunk-size");
            config.chunk_size = parse_decimal(
                take_value(argc, argv, i, "--chunk-size"), "--chunk-size",
                kMaxSubjectBytes, true);
        } else if (option == "--max-matches") {
            mark_once(config.max_matches_seen, "--max-matches");
            config.max_matches = parse_decimal(
                take_value(argc, argv, i, "--max-matches"), "--max-matches",
                kMaxMatchesLimit, true);
        } else if (option == "--min-offset") {
            mark_once(config.min_offset_seen, "--min-offset");
            config.min_offset = parse_decimal(
                take_value(argc, argv, i, "--min-offset"), "--min-offset",
                std::numeric_limits<std::uint64_t>::max(), false);
        } else if (option == "--max-offset") {
            mark_once(config.max_offset_seen, "--max-offset");
            config.max_offset = parse_decimal(
                take_value(argc, argv, i, "--max-offset"), "--max-offset",
                std::numeric_limits<std::uint64_t>::max(), false);
        } else if (option == "--min-length") {
            mark_once(config.min_length_seen, "--min-length");
            config.min_length = parse_decimal(
                take_value(argc, argv, i, "--min-length"), "--min-length",
                std::numeric_limits<std::uint64_t>::max(), false);
        } else if (option == "--edit-distance") {
            mark_once(config.edit_distance_seen, "--edit-distance");
            config.edit_distance = static_cast<std::uint32_t>(parse_decimal(
                take_value(argc, argv, i, "--edit-distance"), "--edit-distance",
                std::numeric_limits<std::uint32_t>::max(), false));
        } else if (option == "--hamming-distance") {
            mark_once(config.hamming_distance_seen, "--hamming-distance");
            config.hamming_distance = static_cast<std::uint32_t>(parse_decimal(
                take_value(argc, argv, i, "--hamming-distance"),
                "--hamming-distance", std::numeric_limits<std::uint32_t>::max(),
                false));
        } else if (option == "--literal") {
            set_boolean(config.literal, "--literal");
        } else if (option == "-i" || option == "--caseless") {
            set_boolean(config.caseless, "--caseless");
        } else if (option == "-s" || option == "--dotall") {
            set_boolean(config.dotall, "--dotall");
        } else if (option == "-m" || option == "--multiline") {
            set_boolean(config.multiline, "--multiline");
        } else if (option == "--single-match") {
            set_boolean(config.single_match, "--single-match");
        } else if (option == "--allow-empty") {
            set_boolean(config.allow_empty, "--allow-empty");
        } else if (option == "--utf8") {
            set_boolean(config.utf8, "--utf8");
        } else if (option == "--ucp") {
            set_boolean(config.ucp, "--ucp");
        } else if (option == "--prefilter") {
            set_boolean(config.prefilter, "--prefilter");
        } else if (option == "--som-leftmost") {
            set_boolean(config.som_leftmost, "--som-leftmost");
        } else {
            throw UsageError(std::string("unknown option or argument: ") + option);
        }
    }
    return config;
}

void validate_config(const Config &config) {
    if (config.expressions.empty() && !config.expression_file_seen) {
        throw UsageError("exactly one pattern source is required");
    }
    if (!config.expressions.empty() && config.expression_file_seen) {
        throw UsageError("--expression and --expression-file cannot be mixed");
    }
    if (config.expression_file_seen && config.expression_file == "-") {
        throw UsageError("--expression-file may not be -");
    }
    if (config.input_seen && config.text_seen) {
        throw UsageError("--input and --text cannot be combined");
    }
    if (config.command == Command::Info &&
        (config.input_seen || config.text_seen || config.chunk_size_seen ||
         config.max_matches_seen)) {
        throw UsageError("scan input options are not valid for info");
    }
    if (config.chunk_size_seen && config.mode == Mode::Block) {
        throw UsageError("--chunk-size requires stream or vectored mode");
    }
    if (config.ucp && !config.utf8) {
        throw UsageError("--ucp requires --utf8");
    }
    if (config.som_leftmost && config.single_match) {
        throw UsageError("--som-leftmost cannot be combined with --single-match");
    }
    if (config.som_leftmost && config.prefilter) {
        throw UsageError("--som-leftmost cannot be combined with --prefilter");
    }
    if (config.horizon_seen &&
        (!config.som_leftmost || config.mode != Mode::Stream)) {
        throw UsageError(
            "--som-horizon requires --mode stream and --som-leftmost");
    }
    if (config.edit_distance_seen && config.hamming_distance_seen) {
        throw UsageError(
            "--edit-distance and --hamming-distance are mutually exclusive");
    }
    if (config.min_offset_seen && config.max_offset_seen &&
        config.min_offset > config.max_offset) {
        throw UsageError("--min-offset may not exceed --max-offset");
    }
    if (config.min_length_seen && config.max_offset_seen &&
        config.min_length > config.max_offset) {
        throw UsageError("--min-length may not exceed --max-offset");
    }
    if (config.literal &&
        (config.dotall || config.multiline || config.allow_empty || config.utf8 ||
         config.ucp || config.prefilter || config.min_offset_seen ||
         config.max_offset_seen || config.min_length_seen ||
         config.edit_distance_seen || config.hamming_distance_seen)) {
        throw UsageError("an option is not supported in literal mode");
    }
}

std::vector<char> read_stream(FILE *stream, std::size_t limit,
                              const std::string &description,
                              bool limit_is_usage) {
    std::vector<char> data;
    char buffer[65536];
    for (;;) {
        const std::size_t count = std::fread(buffer, 1, sizeof(buffer), stream);
        if (count > 0) {
            if (data.size() > limit - count) {
                if (limit_is_usage) {
                    throw UsageError(description + " exceeds its size limit");
                }
                throw RuntimeError(description + " exceeds its size limit");
            }
            data.insert(data.end(), buffer, buffer + count);
        }
        if (count < sizeof(buffer)) {
            if (std::ferror(stream)) {
                throw RuntimeError("failed to read " + description);
            }
            break;
        }
    }
    return data;
}

std::vector<char> read_file(const std::string &path, std::size_t limit,
                            const std::string &description,
                            bool limit_is_usage) {
    FILE *raw = std::fopen(path.c_str(), "rb");
    if (raw == NULL) {
        throw RuntimeError("cannot open " + description + ": " +
                           std::strerror(errno));
    }
    std::unique_ptr<FILE, int (*)(FILE *)> file(raw, std::fclose);
    return read_stream(file.get(), limit, description, limit_is_usage);
}

bool valid_utf8(const std::string &value) {
    const unsigned char *bytes =
        reinterpret_cast<const unsigned char *>(value.data());
    const std::size_t size = value.size();
    std::size_t i = 0;
    while (i < size) {
        const unsigned char first = bytes[i];
        if (first <= 0x7fU) {
            ++i;
            continue;
        }
        std::size_t needed = 0;
        unsigned char second_min = 0x80U;
        unsigned char second_max = 0xbfU;
        if (first >= 0xc2U && first <= 0xdfU) {
            needed = 1;
        } else if (first >= 0xe0U && first <= 0xefU) {
            needed = 2;
            if (first == 0xe0U) {
                second_min = 0xa0U;
            } else if (first == 0xedU) {
                second_max = 0x9fU;
            }
        } else if (first >= 0xf0U && first <= 0xf4U) {
            needed = 3;
            if (first == 0xf0U) {
                second_min = 0x90U;
            } else if (first == 0xf4U) {
                second_max = 0x8fU;
            }
        } else {
            return false;
        }
        if (i + needed >= size || bytes[i + 1] < second_min ||
            bytes[i + 1] > second_max) {
            return false;
        }
        for (std::size_t j = 2; j <= needed; ++j) {
            if (bytes[i + j] < 0x80U || bytes[i + j] > 0xbfU) {
                return false;
            }
        }
        i += needed + 1;
    }
    return true;
}

bool valid_utf8(const std::vector<char> &value) {
    return valid_utf8(std::string(value.begin(), value.end()));
}

std::vector<std::string> split_expression_file(const std::vector<char> &data) {
    if (data.empty()) {
        throw UsageError("expression file is empty");
    }
    std::vector<std::string> patterns;
    std::size_t start = 0;
    while (start < data.size()) {
        std::size_t end = start;
        while (end < data.size() && data[end] != '\n') {
            ++end;
        }
        std::size_t record_end = end;
        if (end < data.size() && record_end > start &&
            data[record_end - 1] == '\r') {
            --record_end;
        }
        patterns.push_back(
            std::string(data.data() + start, data.data() + record_end));
        if (end == data.size()) {
            break;
        }
        start = end + 1;
    }
    return patterns;
}

std::vector<std::string> load_patterns(const Config &config) {
    std::vector<std::string> patterns = config.expressions;
    if (config.expression_file_seen) {
        patterns = split_expression_file(
            read_file(config.expression_file, kMaxExpressionFileBytes,
                      "expression file", true));
    }
    if (patterns.empty()) {
        throw UsageError("pattern source contains no expressions");
    }
    if (patterns.size() > kMaxPatterns) {
        throw UsageError("pattern source contains more than 10000 expressions");
    }
    std::size_t total = 0;
    for (std::size_t i = 0; i < patterns.size(); ++i) {
        if (patterns[i].size() > kMaxPatternBytes) {
            throw UsageError("pattern exceeds 8192 bytes");
        }
        if (total > kMaxExpressionBytes - patterns[i].size()) {
            throw UsageError("cumulative expression bytes exceed 8 MiB");
        }
        total += patterns[i].size();
        if (config.literal && patterns[i].empty()) {
            throw UsageError("literal pattern may not be empty");
        }
        if (!config.literal && patterns[i].find('\0') != std::string::npos) {
            throw UsageError("regex pattern contains an embedded NUL byte");
        }
        if (config.utf8 && !valid_utf8(patterns[i])) {
            throw UsageError("pattern is not valid UTF-8");
        }
    }
    return patterns;
}

std::vector<char> load_subject(const Config &config) {
    if (config.text_seen) {
        return std::vector<char>(config.text.begin(), config.text.end());
    }
    if (!config.input_seen || config.input_path == "-") {
        return read_stream(stdin, kMaxSubjectBytes, "standard input", false);
    }
    return read_file(config.input_path, kMaxSubjectBytes, "input file", false);
}

unsigned compile_mode(const Config &config) {
    unsigned mode = HS_MODE_BLOCK;
    if (config.mode == Mode::Stream) {
        mode = HS_MODE_STREAM;
        if (config.som_leftmost) {
            if (config.horizon == Horizon::Small) {
                mode |= HS_MODE_SOM_HORIZON_SMALL;
            } else if (config.horizon == Horizon::Medium) {
                mode |= HS_MODE_SOM_HORIZON_MEDIUM;
            } else {
                mode |= HS_MODE_SOM_HORIZON_LARGE;
            }
        }
    } else if (config.mode == Mode::Vectored) {
        mode = HS_MODE_VECTORED;
    }
    return mode;
}

unsigned compile_flags(const Config &config) {
    unsigned flags = 0;
    if (config.caseless) {
        flags |= HS_FLAG_CASELESS;
    }
    if (config.dotall) {
        flags |= HS_FLAG_DOTALL;
    }
    if (config.multiline) {
        flags |= HS_FLAG_MULTILINE;
    }
    if (config.single_match) {
        flags |= HS_FLAG_SINGLEMATCH;
    }
    if (config.allow_empty) {
        flags |= HS_FLAG_ALLOWEMPTY;
    }
    if (config.utf8) {
        flags |= HS_FLAG_UTF8;
    }
    if (config.ucp) {
        flags |= HS_FLAG_UCP;
    }
    if (config.prefilter) {
        flags |= HS_FLAG_PREFILTER;
    }
    if (config.som_leftmost) {
        flags |= HS_FLAG_SOM_LEFTMOST;
    }
    return flags;
}

DatabasePtr compile_database(const Config &config,
                             const std::vector<std::string> &patterns) {
    std::vector<const char *> expressions;
    std::vector<unsigned> flags(patterns.size(), compile_flags(config));
    std::vector<unsigned> ids;
    expressions.reserve(patterns.size());
    ids.reserve(patterns.size());
    for (std::size_t i = 0; i < patterns.size(); ++i) {
        expressions.push_back(patterns[i].data());
        ids.push_back(static_cast<unsigned>(i + 1));
    }

    hs_database_t *raw_database = NULL;
    hs_compile_error_t *compile_error = NULL;
    hs_error_t status = HS_SUCCESS;
    if (config.literal) {
        std::vector<std::size_t> lengths;
        lengths.reserve(patterns.size());
        for (std::size_t i = 0; i < patterns.size(); ++i) {
            lengths.push_back(patterns[i].size());
        }
        status = hs_compile_lit_multi(
            expressions.data(), flags.data(), ids.data(), lengths.data(),
            static_cast<unsigned>(patterns.size()), compile_mode(config), NULL,
            &raw_database, &compile_error);
    } else {
        std::vector<hs_expr_ext_t> extensions(patterns.size());
        std::vector<const hs_expr_ext_t *> extension_pointers(patterns.size());
        const bool has_extensions =
            config.min_offset_seen || config.max_offset_seen ||
            config.min_length_seen || config.edit_distance_seen ||
            config.hamming_distance_seen;
        for (std::size_t i = 0; i < extensions.size(); ++i) {
            hs_expr_ext_t &extension = extensions[i];
            if (config.min_offset_seen) {
                extension.flags |= HS_EXT_FLAG_MIN_OFFSET;
                extension.min_offset = config.min_offset;
            }
            if (config.max_offset_seen) {
                extension.flags |= HS_EXT_FLAG_MAX_OFFSET;
                extension.max_offset = config.max_offset;
            }
            if (config.min_length_seen) {
                extension.flags |= HS_EXT_FLAG_MIN_LENGTH;
                extension.min_length = config.min_length;
            }
            if (config.edit_distance_seen) {
                extension.flags |= HS_EXT_FLAG_EDIT_DISTANCE;
                extension.edit_distance = config.edit_distance;
            }
            if (config.hamming_distance_seen) {
                extension.flags |= HS_EXT_FLAG_HAMMING_DISTANCE;
                extension.hamming_distance = config.hamming_distance;
            }
            extension_pointers[i] = has_extensions ? &extension : NULL;
        }
        status = hs_compile_ext_multi(
            expressions.data(), flags.data(), ids.data(),
            has_extensions ? extension_pointers.data() : NULL,
            static_cast<unsigned>(patterns.size()), compile_mode(config), NULL,
            &raw_database, &compile_error);
    }

    if (status != HS_SUCCESS) {
        std::string message = "Hyperscan compilation failed";
        int expression = -1;
        if (compile_error != NULL) {
            if (compile_error->message != NULL) {
                message = compile_error->message;
            }
            expression = compile_error->expression;
            (void)hs_free_compile_error(compile_error);
        }
        const bool allocation_failure =
            message.find("allocate memory") != std::string::npos ||
            message.find("memory allocation") != std::string::npos ||
            message.find("out of memory") != std::string::npos;
        if (status == HS_COMPILER_ERROR && !allocation_failure) {
            if (expression >= 0) {
                std::ostringstream diagnostic;
                diagnostic << "pattern " << (expression + 1) << ": " << message;
                throw UsageError(diagnostic.str());
            }
            throw UsageError(message);
        }
        std::ostringstream diagnostic;
        diagnostic << message << " (Hyperscan status " << status << ')';
        throw RuntimeError(diagnostic.str());
    }
    if (compile_error != NULL) {
        (void)hs_free_compile_error(compile_error);
    }
    return DatabasePtr(raw_database);
}

ScratchPtr allocate_scratch(const DatabasePtr &database) {
    hs_scratch_t *raw_scratch = NULL;
    const hs_error_t status = hs_alloc_scratch(database.get(), &raw_scratch);
    if (status != HS_SUCCESS) {
        std::ostringstream message;
        message << "cannot allocate scratch space (Hyperscan status " << status
                << ')';
        throw RuntimeError(message.str());
    }
    return ScratchPtr(raw_scratch);
}

#ifdef REGEX_UTILS_HYPERSCAN_TEST_SEAMS
void *fail_allocation(std::size_t) { return NULL; }

void free_test_allocation(void *allocation) { std::free(allocation); }

void configure_allocator_test_seam() {
    const char *requested =
        std::getenv("REGEX_UTILS_HYPERSCAN_TEST_FAIL_ALLOCATOR");
    if (requested == NULL) {
        return;
    }

    hs_error_t status = HS_INVALID;
    const std::string allocator(requested);
    if (allocator == "database") {
        status = hs_set_database_allocator(fail_allocation, free_test_allocation);
    } else if (allocator == "scratch") {
        status = hs_set_scratch_allocator(fail_allocation, free_test_allocation);
    } else if (allocator == "stream") {
        status = hs_set_stream_allocator(fail_allocation, free_test_allocation);
    } else {
        throw RuntimeError("invalid internal allocator test seam");
    }
    if (status != HS_SUCCESS) {
        std::ostringstream message;
        message << "allocator test setup failed (Hyperscan status " << status
                << ')';
        throw RuntimeError(message.str());
    }
}
#else
void configure_allocator_test_seam() {}
#endif

const char *mode_name(Mode mode) {
    if (mode == Mode::Stream) {
        return "stream";
    }
    if (mode == Mode::Vectored) {
        return "vectored";
    }
    return "block";
}

void require_hs_success(hs_error_t status, const char *operation) {
    if (status != HS_SUCCESS) {
        std::ostringstream message;
        message << operation << " failed (Hyperscan status " << status << ')';
        throw RuntimeError(message.str());
    }
}

std::string info_output(const Config &config,
                        const std::vector<std::string> &patterns,
                        const DatabasePtr &database, const ScratchPtr &scratch) {
    std::size_t database_bytes = 0;
    std::size_t scratch_bytes = 0;
    std::size_t stream_bytes = 0;
    require_hs_success(hs_database_size(database.get(), &database_bytes),
                       "database size query");
    require_hs_success(hs_scratch_size(scratch.get(), &scratch_bytes),
                       "scratch size query");
    if (config.mode == Mode::Stream) {
        require_hs_success(hs_stream_size(database.get(), &stream_bytes),
                           "stream size query");
    }

    std::ostringstream output;
    output << "{\"source_tag\":\"" << REGEX_UTILS_HYPERSCAN_SOURCE_TAG
           << "\",\"library_version\":\"" << hs_version()
           << "\",\"compile_kind\":\""
           << (config.literal ? "literal" : "regex") << "\",\"mode\":\""
           << mode_name(config.mode) << "\",\"patterns\":" << patterns.size()
           << ",\"database_bytes\":" << database_bytes
           << ",\"scratch_bytes\":" << scratch_bytes << ",\"stream_bytes\":";
    if (config.mode == Mode::Stream) {
        output << stream_bytes;
    } else {
        output << "null";
    }
    output << "}\n";
    return output.str();
}

struct MatchEvent {
    unsigned id;
    unsigned long long start;
    unsigned long long end;
    bool start_available;
    bool past_horizon;
};

struct MatchContext {
    std::vector<MatchEvent> events;
    std::size_t limit;
    bool som;
    bool limit_exceeded;
};

int on_match(unsigned id, unsigned long long from, unsigned long long to,
             unsigned, void *raw_context) {
    MatchContext *context = static_cast<MatchContext *>(raw_context);
    if (context->events.size() >= context->limit) {
        context->limit_exceeded = true;
        return 1;
    }
    MatchEvent event;
    event.id = id;
    event.start = from;
    event.end = to;
    event.start_available = context->som && from != HS_OFFSET_PAST_HORIZON;
    event.past_horizon = context->som && from == HS_OFFSET_PAST_HORIZON;
    context->events.push_back(event);
    return 0;
}

void check_scan_status(hs_error_t status, const MatchContext &context,
                       const char *operation) {
    if (status == HS_SUCCESS) {
        return;
    }
    if (status == HS_SCAN_TERMINATED && context.limit_exceeded) {
        return;
    }
    std::ostringstream message;
    message << operation << " failed (Hyperscan status " << status << ')';
    throw RuntimeError(message.str());
}

void scan_block(const DatabasePtr &database, const ScratchPtr &scratch,
                const std::vector<char> &subject, MatchContext &context) {
    static const char empty = '\0';
    const char *data = subject.empty() ? &empty : subject.data();
    const hs_error_t status = hs_scan(
        database.get(), data, static_cast<unsigned>(subject.size()), 0,
        scratch.get(), on_match, &context);
    check_scan_status(status, context, "block scan");
}

void scan_vectored(const Config &config, const DatabasePtr &database,
                   const ScratchPtr &scratch, const std::vector<char> &subject,
                   MatchContext &context) {
    static const char empty = '\0';
    std::vector<const char *> chunks;
    std::vector<unsigned> lengths;
    if (subject.empty()) {
        chunks.push_back(&empty);
        lengths.push_back(0);
    } else {
        const std::size_t chunk_size = static_cast<std::size_t>(config.chunk_size);
        for (std::size_t offset = 0; offset < subject.size(); offset += chunk_size) {
            const std::size_t remaining = subject.size() - offset;
            const std::size_t length = remaining < chunk_size ? remaining : chunk_size;
            chunks.push_back(subject.data() + offset);
            lengths.push_back(static_cast<unsigned>(length));
        }
    }
    const hs_error_t status = hs_scan_vector(
        database.get(), chunks.data(), lengths.data(),
        static_cast<unsigned>(chunks.size()), 0, scratch.get(), on_match,
        &context);
    check_scan_status(status, context, "vectored scan");
}

void scan_stream(const Config &config, const DatabasePtr &database,
                 const ScratchPtr &scratch, const std::vector<char> &subject,
                 MatchContext &context) {
    hs_stream_t *stream = NULL;
    require_hs_success(hs_open_stream(database.get(), 0, &stream),
                       "stream open");

    hs_error_t scan_status = HS_SUCCESS;
    const std::size_t chunk_size = static_cast<std::size_t>(config.chunk_size);
    for (std::size_t offset = 0;
         offset < subject.size() && scan_status == HS_SUCCESS;
         offset += chunk_size) {
        const std::size_t remaining = subject.size() - offset;
        const std::size_t length = remaining < chunk_size ? remaining : chunk_size;
        scan_status = hs_scan_stream(
            stream, subject.data() + offset, static_cast<unsigned>(length), 0,
            scratch.get(), on_match, &context);
    }
    const hs_error_t close_status =
        hs_close_stream(stream, scratch.get(), on_match, &context);
    check_scan_status(scan_status, context, "stream scan");
    check_scan_status(close_status, context, "stream close");
}

std::string scan_output(const Config &config, const DatabasePtr &database,
                        const ScratchPtr &scratch,
                        const std::vector<char> &subject) {
    MatchContext context;
    context.limit = static_cast<std::size_t>(config.max_matches);
    context.som = config.som_leftmost;
    context.limit_exceeded = false;
    context.events.reserve(context.limit);

    if (config.mode == Mode::Block) {
        scan_block(database, scratch, subject, context);
    } else if (config.mode == Mode::Vectored) {
        scan_vectored(config, database, scratch, subject, context);
    } else {
        scan_stream(config, database, scratch, subject, context);
    }
    if (context.limit_exceeded) {
        throw RuntimeError("match limit exceeded");
    }

    std::ostringstream output;
    for (std::size_t i = 0; i < context.events.size(); ++i) {
        const MatchEvent &event = context.events[i];
        output << "{\"id\":" << event.id << ",\"start\":";
        if (event.start_available) {
            output << event.start;
        } else {
            output << "null";
        }
        output << ",\"end\":" << event.end << ",\"start_status\":\"";
        if (event.past_horizon) {
            output << "past_horizon";
        } else if (event.start_available) {
            output << "available";
        } else {
            output << "disabled";
        }
        output << "\"}\n";
    }
    return output.str();
}

int write_stdout(const std::string &output) {
    std::size_t offset = 0;
    while (offset < output.size()) {
        errno = 0;
        const std::size_t written =
            std::fwrite(output.data() + offset, 1, output.size() - offset, stdout);
        offset += written;
        if (written == 0) {
            if (errno == EPIPE) {
                return 0;
            }
            throw RuntimeError("failed to write stdout");
        }
    }
    errno = 0;
    if (std::fflush(stdout) != 0) {
        if (errno == EPIPE) {
            return 0;
        }
        throw RuntimeError("failed to flush stdout");
    }
    return 0;
}

int run(int argc, char **argv) {
    if (argc == 2 && (std::string(argv[1]) == "--help" ||
                      std::string(argv[1]) == "-h")) {
        return write_stdout(kHelp);
    }
    if (argc == 2 && std::string(argv[1]) == "--version") {
        std::ostringstream version;
        version << "hyperscan " << REGEX_UTILS_HYPERSCAN_SOURCE_TAG
                << " (Hyperscan " << hs_version() << ")\n";
        return write_stdout(version.str());
    }

    const Config config = parse_arguments(argc, argv);
    validate_config(config);
    const hs_error_t platform_status = hs_valid_platform();
    if (platform_status != HS_SUCCESS) {
        std::ostringstream message;
        message << "unsupported CPU platform (Hyperscan status " << platform_status
                << ')';
        throw RuntimeError(message.str());
    }
    configure_allocator_test_seam();

    const std::vector<std::string> patterns = load_patterns(config);
    const DatabasePtr database = compile_database(config, patterns);
    const ScratchPtr scratch = allocate_scratch(database);
    if (config.command == Command::Info) {
        return write_stdout(info_output(config, patterns, database, scratch));
    }

    const std::vector<char> subject = load_subject(config);
    if (config.utf8 && !valid_utf8(subject)) {
        throw UsageError("subject is not valid UTF-8");
    }
    return write_stdout(scan_output(config, database, scratch, subject));
}

} // namespace

int main(int argc, char **argv) {
    (void)std::signal(SIGPIPE, SIG_IGN);
    try {
        return run(argc, argv);
    } catch (const CliError &error) {
        std::fprintf(stderr, "hyperscan: %s\n", error.what());
        return error.status();
    } catch (const std::bad_alloc &) {
        std::fprintf(stderr, "hyperscan: memory allocation failed\n");
        return 1;
    } catch (const std::exception &error) {
        std::fprintf(stderr, "hyperscan: unexpected failure: %s\n", error.what());
        return 1;
    }
}
