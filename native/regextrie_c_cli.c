#include <errno.h>
#include <limits.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "trie.h"

#define PROGRAM "regextrie-c"
#define MAX_RECORD_BYTES ((size_t)1024)
#define MAX_SOURCE_BYTES ((size_t)16 * 1024 * 1024)
#define MAX_REGEX_RECORD_BYTES ((size_t)16)
#define MAX_REGEX_EXPANSION ((size_t)65536)

typedef enum {
    INSERT_REGEX,
    INSERT_WORD
} InsertMode;

typedef struct {
    char **items;
    size_t count;
    size_t capacity;
} StringList;

typedef struct {
    unsigned char *data;
    size_t length;
    size_t capacity;
} ByteBuffer;

typedef struct {
    StringList dictionary;
    StringList queries;
    const char *input_path;
    const char *query_input_path;
    InsertMode mode;
    bool mode_seen;
} Options;

static size_t allocations_until_failure = SIZE_MAX;

static void initialize_allocation_hook(void) {
    const char *value = getenv("REGEX_UTILS_CLI_TEST_FAIL_ALLOC_AFTER");
    char *end = NULL;
    unsigned long long parsed;

    if (value == NULL || *value == '\0') {
        return;
    }
    errno = 0;
    parsed = strtoull(value, &end, 10);
    if (errno == 0 && end != value && *end == '\0' && parsed <= SIZE_MAX) {
        allocations_until_failure = (size_t)parsed;
    }
}

static bool allocation_should_fail(void) {
    if (allocations_until_failure == SIZE_MAX) {
        return false;
    }
    if (allocations_until_failure == 0) {
        return true;
    }
    --allocations_until_failure;
    return false;
}

static void *checked_malloc(size_t size) {
    if (allocation_should_fail()) {
        return NULL;
    }
    return malloc(size == 0 ? 1 : size);
}

static void *checked_realloc(void *pointer, size_t size) {
    if (allocation_should_fail()) {
        return NULL;
    }
    return realloc(pointer, size == 0 ? 1 : size);
}

static int diagnostic(int status, const char *message) {
    fprintf(stderr, "%s: %s\n", PROGRAM, message);
    return status;
}

static int diagnostic_path(int status, const char *prefix, const char *path) {
    fprintf(stderr, "%s: %s '%s': %s\n", PROGRAM, prefix, path, strerror(errno));
    return status;
}

static void string_list_free(StringList *list) {
    size_t index;
    for (index = 0; index < list->count; ++index) {
        free(list->items[index]);
    }
    free(list->items);
    list->items = NULL;
    list->count = 0;
    list->capacity = 0;
}

static bool string_list_push(StringList *list, const unsigned char *data, size_t length) {
    char *copy;
    if (list->count == list->capacity) {
        size_t new_capacity = list->capacity == 0 ? 8 : list->capacity * 2;
        char **new_items;
        if (new_capacity < list->capacity || new_capacity > SIZE_MAX / sizeof(*new_items)) {
            return false;
        }
        new_items = checked_realloc(list->items, new_capacity * sizeof(*new_items));
        if (new_items == NULL) {
            return false;
        }
        list->items = new_items;
        list->capacity = new_capacity;
    }
    copy = checked_malloc(length + 1);
    if (copy == NULL) {
        return false;
    }
    if (length != 0) {
        memcpy(copy, data, length);
    }
    copy[length] = '\0';
    list->items[list->count++] = copy;
    return true;
}

static bool valid_utf8(const unsigned char *data, size_t length) {
    size_t index = 0;
    while (index < length) {
        unsigned char first = data[index];
        if (first <= 0x7f) {
            ++index;
        } else if (first >= 0xc2 && first <= 0xdf) {
            if (index + 1 >= length || data[index + 1] < 0x80 || data[index + 1] > 0xbf) {
                return false;
            }
            index += 2;
        } else if (first == 0xe0) {
            if (index + 2 >= length || data[index + 1] < 0xa0 || data[index + 1] > 0xbf ||
                data[index + 2] < 0x80 || data[index + 2] > 0xbf) {
                return false;
            }
            index += 3;
        } else if ((first >= 0xe1 && first <= 0xec) || (first >= 0xee && first <= 0xef)) {
            if (index + 2 >= length || data[index + 1] < 0x80 || data[index + 1] > 0xbf ||
                data[index + 2] < 0x80 || data[index + 2] > 0xbf) {
                return false;
            }
            index += 3;
        } else if (first == 0xed) {
            if (index + 2 >= length || data[index + 1] < 0x80 || data[index + 1] > 0x9f ||
                data[index + 2] < 0x80 || data[index + 2] > 0xbf) {
                return false;
            }
            index += 3;
        } else if (first == 0xf0) {
            if (index + 3 >= length || data[index + 1] < 0x90 || data[index + 1] > 0xbf ||
                data[index + 2] < 0x80 || data[index + 2] > 0xbf ||
                data[index + 3] < 0x80 || data[index + 3] > 0xbf) {
                return false;
            }
            index += 4;
        } else if (first >= 0xf1 && first <= 0xf3) {
            if (index + 3 >= length || data[index + 1] < 0x80 || data[index + 1] > 0xbf ||
                data[index + 2] < 0x80 || data[index + 2] > 0xbf ||
                data[index + 3] < 0x80 || data[index + 3] > 0xbf) {
                return false;
            }
            index += 4;
        } else if (first == 0xf4) {
            if (index + 3 >= length || data[index + 1] < 0x80 || data[index + 1] > 0x8f ||
                data[index + 2] < 0x80 || data[index + 2] > 0xbf ||
                data[index + 3] < 0x80 || data[index + 3] > 0xbf) {
                return false;
            }
            index += 4;
        } else {
            return false;
        }
    }
    return true;
}

static int validate_record(const unsigned char *data, size_t length, const char *kind) {
    if (length > MAX_RECORD_BYTES) {
        fprintf(stderr, "%s: %s record exceeds 1024 bytes\n", PROGRAM, kind);
        return 1;
    }
    if (length != 0 && memchr(data, '\0', length) != NULL) {
        fprintf(stderr, "%s: %s record contains NUL\n", PROGRAM, kind);
        return 1;
    }
    if (!valid_utf8(data, length)) {
        fprintf(stderr, "%s: %s input is not valid UTF-8\n", PROGRAM, kind);
        return 1;
    }
    return 0;
}

static int push_argv_record(StringList *list, const char *value, const char *kind) {
    size_t length = strlen(value);
    int status = validate_record((const unsigned char *)value, length, kind);
    if (status != 0) {
        return status;
    }
    if (!string_list_push(list, (const unsigned char *)value, length)) {
        return diagnostic(1, "cannot allocate record storage");
    }
    return 0;
}

static void print_help(void) {
    fputs("Usage:\n"
          "  regextrie-c [OPTIONS] [WORD...]\n\n"
          "Dictionary input:\n"
          "  WORD...                         Dictionary records as separate arguments\n"
          "  -i, --input FILE                Read LF/CRLF-delimited dictionary records;\n"
          "                                  use - for stdin\n"
          "  -m, --insert-mode word|regex    Call add_word or add_regex [default: regex]\n\n"
          "Queries:\n"
          "  -q, --query QUERY               Query with find_word; repeatable\n"
          "  -Q, --query-input FILE          Read LF/CRLF-delimited queries; use - for stdin\n\n"
          "Other:\n"
          "  -h, --help                      Show help\n"
          "  -V, --version                   Show wrapper and pinned source versions\n",
          stdout);
}

static bool option_takes_value(const char *argument) {
    return strcmp(argument, "-i") == 0 || strcmp(argument, "--input") == 0 ||
           strcmp(argument, "-m") == 0 || strcmp(argument, "--insert-mode") == 0 ||
           strcmp(argument, "-q") == 0 || strcmp(argument, "--query") == 0 ||
           strcmp(argument, "-Q") == 0 || strcmp(argument, "--query-input") == 0;
}

static int parse_options(int argc, char **argv, Options *options, bool *finished) {
    int index;
    bool options_ended = false;
    *finished = false;

    for (index = 1; index < argc; ++index) {
        const char *argument = argv[index];
        if (!options_ended && strcmp(argument, "--") == 0) {
            options_ended = true;
            continue;
        }
        if (!options_ended && (strcmp(argument, "-h") == 0 || strcmp(argument, "--help") == 0)) {
            print_help();
            *finished = true;
            return 0;
        }
        if (!options_ended && (strcmp(argument, "-V") == 0 || strcmp(argument, "--version") == 0)) {
            puts("regextrie-c 0.0.0 (RegexTrie c35e88931f64)");
            *finished = true;
            return 0;
        }
        if (!options_ended && option_takes_value(argument)) {
            const char *value;
            if (++index >= argc) {
                fprintf(stderr, "%s: option requires a value: %s\n", PROGRAM, argument);
                return 2;
            }
            value = argv[index];
            if (strcmp(argument, "-i") == 0 || strcmp(argument, "--input") == 0) {
                if (options->input_path != NULL) {
                    return diagnostic(2, "--input may not be repeated");
                }
                options->input_path = value;
            } else if (strcmp(argument, "-m") == 0 || strcmp(argument, "--insert-mode") == 0) {
                if (options->mode_seen) {
                    return diagnostic(2, "--insert-mode may not be repeated");
                }
                options->mode_seen = true;
                if (strcmp(value, "word") == 0) {
                    options->mode = INSERT_WORD;
                } else if (strcmp(value, "regex") == 0) {
                    options->mode = INSERT_REGEX;
                } else {
                    return diagnostic(2, "--insert-mode must be word or regex");
                }
            } else if (strcmp(argument, "-q") == 0 || strcmp(argument, "--query") == 0) {
                int status = push_argv_record(&options->queries, value, "query");
                if (status != 0) {
                    return status;
                }
            } else {
                if (options->query_input_path != NULL) {
                    return diagnostic(2, "--query-input may not be repeated");
                }
                options->query_input_path = value;
            }
            continue;
        }
        if (!options_ended && argument[0] == '-') {
            fprintf(stderr, "%s: unknown or unsupported option: %s\n", PROGRAM, argument);
            return 2;
        }
        {
            int status = push_argv_record(&options->dictionary, argument, "dictionary");
            if (status != 0) {
                return status;
            }
        }
    }

    if (options->input_path != NULL && options->dictionary.count != 0) {
        return diagnostic(2, "dictionary arguments cannot be combined with --input");
    }
    if (options->input_path == NULL && options->dictionary.count == 0) {
        return diagnostic(2, "provide dictionary arguments or --input");
    }
    if (options->query_input_path != NULL && options->queries.count != 0) {
        return diagnostic(2, "--query cannot be combined with --query-input");
    }
    if (options->query_input_path == NULL && options->queries.count == 0) {
        return diagnostic(2, "provide at least one --query or --query-input");
    }
    if (options->input_path != NULL && options->query_input_path != NULL &&
        strcmp(options->input_path, "-") == 0 && strcmp(options->query_input_path, "-") == 0) {
        return diagnostic(2, "dictionary and query input cannot both read stdin");
    }
    return 0;
}

static int byte_buffer_reserve(ByteBuffer *buffer, size_t additional) {
    size_t needed;
    size_t capacity;
    unsigned char *data;
    if (additional > SIZE_MAX - buffer->length) {
        return diagnostic(1, "output size overflow");
    }
    needed = buffer->length + additional;
    if (needed <= buffer->capacity) {
        return 0;
    }
    capacity = buffer->capacity == 0 ? 4096 : buffer->capacity;
    while (capacity < needed) {
        if (capacity > SIZE_MAX / 2) {
            capacity = needed;
            break;
        }
        capacity *= 2;
    }
    data = checked_realloc(buffer->data, capacity);
    if (data == NULL) {
        return diagnostic(1, "cannot allocate output buffer");
    }
    buffer->data = data;
    buffer->capacity = capacity;
    return 0;
}

static int byte_buffer_append(ByteBuffer *buffer, const void *data, size_t length) {
    int status = byte_buffer_reserve(buffer, length);
    if (status != 0) {
        return status;
    }
    if (length != 0) {
        memcpy(buffer->data + buffer->length, data, length);
    }
    buffer->length += length;
    return 0;
}

static int byte_buffer_append_literal(ByteBuffer *buffer, const char *text) {
    return byte_buffer_append(buffer, text, strlen(text));
}

static int append_json_string(ByteBuffer *buffer, const char *text) {
    const unsigned char *cursor = (const unsigned char *)text;
    int status = byte_buffer_append_literal(buffer, "\"");
    if (status != 0) {
        return status;
    }
    while (*cursor != '\0') {
        const char *escape = NULL;
        char unicode_escape[7];
        switch (*cursor) {
            case '"': escape = "\\\""; break;
            case '\\': escape = "\\\\"; break;
            case '\b': escape = "\\b"; break;
            case '\f': escape = "\\f"; break;
            case '\n': escape = "\\n"; break;
            case '\r': escape = "\\r"; break;
            case '\t': escape = "\\t"; break;
            default: break;
        }
        if (escape != NULL) {
            status = byte_buffer_append_literal(buffer, escape);
        } else if (*cursor < 0x20) {
            static const char digits[] = "0123456789abcdef";
            unicode_escape[0] = '\\';
            unicode_escape[1] = 'u';
            unicode_escape[2] = '0';
            unicode_escape[3] = '0';
            unicode_escape[4] = digits[*cursor >> 4];
            unicode_escape[5] = digits[*cursor & 0x0f];
            unicode_escape[6] = '\0';
            status = byte_buffer_append_literal(buffer, unicode_escape);
        } else {
            status = byte_buffer_append(buffer, cursor, 1);
        }
        if (status != 0) {
            return status;
        }
        ++cursor;
    }
    return byte_buffer_append_literal(buffer, "\"");
}

static int read_source_bytes(const char *path, const char *kind, ByteBuffer *source) {
    FILE *stream;
    unsigned char chunk[8192];
    bool close_stream;

    if (strcmp(path, "-") == 0) {
        stream = stdin;
        close_stream = false;
    } else {
        stream = fopen(path, "rb");
        if (stream == NULL) {
            return diagnostic_path(1, "cannot open input", path);
        }
        close_stream = true;
    }

    for (;;) {
        size_t count = fread(chunk, 1, sizeof(chunk), stream);
        if (count != 0) {
            if (count > MAX_SOURCE_BYTES - source->length) {
                if (close_stream) {
                    fclose(stream);
                }
                fprintf(stderr, "%s: %s source exceeds 16 MiB\n", PROGRAM, kind);
                return 1;
            }
            if (byte_buffer_append(source, chunk, count) != 0) {
                if (close_stream) {
                    fclose(stream);
                }
                return 1;
            }
        }
        if (count < sizeof(chunk)) {
            if (ferror(stream)) {
                int saved_errno = errno;
                if (close_stream) {
                    fclose(stream);
                }
                errno = saved_errno;
                return diagnostic_path(1, "cannot read input", path);
            }
            break;
        }
    }
    if (close_stream && fclose(stream) != 0) {
        return diagnostic_path(1, "cannot close input", path);
    }
    return 0;
}

static int split_source_records(const ByteBuffer *source, StringList *records, const char *kind) {
    size_t start = 0;
    size_t index;
    if (source->length != 0 && memchr(source->data, '\0', source->length) != NULL) {
        fprintf(stderr, "%s: %s input contains NUL\n", PROGRAM, kind);
        return 1;
    }
    if (!valid_utf8(source->data, source->length)) {
        fprintf(stderr, "%s: %s input is not valid UTF-8\n", PROGRAM, kind);
        return 1;
    }
    for (index = 0; index < source->length; ++index) {
        if (source->data[index] == '\n') {
            size_t end = index;
            int status;
            if (end > start && source->data[end - 1] == '\r') {
                --end;
            }
            status = validate_record(source->data + start, end - start, kind);
            if (status != 0) {
                return status;
            }
            if (!string_list_push(records, source->data + start, end - start)) {
                return diagnostic(1, "cannot allocate record storage");
            }
            start = index + 1;
        }
    }
    if (start < source->length) {
        int status = validate_record(source->data + start, source->length - start, kind);
        if (status != 0) {
            return status;
        }
        if (!string_list_push(records, source->data + start, source->length - start)) {
            return diagnostic(1, "cannot allocate record storage");
        }
    }
    return 0;
}

static int load_source(const char *path, StringList *records, const char *kind) {
    ByteBuffer source = {0};
    int status = read_source_bytes(path, kind, &source);
    if (status == 0) {
        status = split_source_records(&source, records, kind);
    }
    free(source.data);
    return status;
}

static int preflight_regex_expansion(const StringList *dictionary) {
    size_t total = 0;
    size_t index;
    for (index = 0; index < dictionary->count; ++index) {
        size_t length = strlen(dictionary->items[index]);
        size_t expansion;
        if (length > MAX_REGEX_RECORD_BYTES) {
            return diagnostic(1, "regex-mode dictionary record exceeds 16 bytes");
        }
        expansion = ((size_t)1) << length;
        if (expansion > MAX_REGEX_EXPANSION - total) {
            return diagnostic(1, "regex-mode expansion exceeds 65536 paths");
        }
        total += expansion;
    }
    return 0;
}

static int build_output(const Options *options, ByteBuffer *output) {
    Trie *trie;
    size_t index;
    const char *mode_name = options->mode == INSERT_WORD ? "word" : "regex";

    trie = new_trie();
    for (index = 0; index < options->dictionary.count; ++index) {
        if (options->mode == INSERT_WORD) {
            add_word(trie, options->dictionary.items[index]);
        } else {
            add_regex(trie, options->dictionary.items[index]);
        }
    }

    for (index = 0; index < options->queries.count; ++index) {
        int found = find_word(trie, options->queries.items[index]);
        int status = byte_buffer_append_literal(output, "{\"query\":");
        if (status == 0) {
            status = append_json_string(output, options->queries.items[index]);
        }
        if (status == 0) {
            status = byte_buffer_append_literal(output, found != 0 ? ",\"found\":true" : ",\"found\":false");
        }
        if (status == 0) {
            status = byte_buffer_append_literal(output, ",\"insert_mode\":\"");
        }
        if (status == 0) {
            status = byte_buffer_append_literal(output, mode_name);
        }
        if (status == 0) {
            status = byte_buffer_append_literal(output, "\"}\n");
        }
        if (status != 0) {
            free_trie(trie);
            return status;
        }
    }
    free_trie(trie);
    return 0;
}

static int write_output(const ByteBuffer *output) {
    size_t written;
#ifndef _WIN32
    (void)signal(SIGPIPE, SIG_IGN);
#endif
    errno = 0;
    written = fwrite(output->data, 1, output->length, stdout);
    if (written != output->length) {
        if (errno == EPIPE) {
            return 0;
        }
        return diagnostic(1, "cannot write stdout");
    }
    if (fflush(stdout) != 0) {
        if (errno == EPIPE) {
            return 0;
        }
        return diagnostic(1, "cannot flush stdout");
    }
    return 0;
}

int main(int argc, char **argv) {
    Options options = {0};
    ByteBuffer output = {0};
    bool finished;
    int status;

    options.mode = INSERT_REGEX;
    initialize_allocation_hook();
    status = parse_options(argc, argv, &options, &finished);
    if (status != 0 || finished) {
        string_list_free(&options.dictionary);
        string_list_free(&options.queries);
        return status;
    }

    if (options.input_path != NULL) {
        status = load_source(options.input_path, &options.dictionary, "dictionary");
    }
    if (status == 0 && options.query_input_path != NULL) {
        status = load_source(options.query_input_path, &options.queries, "query");
        if (status == 0 && options.queries.count == 0) {
            status = diagnostic(1, "query input contains no records");
        }
    }
    if (status == 0 && options.mode == INSERT_REGEX) {
        status = preflight_regex_expansion(&options.dictionary);
    }
    if (status == 0) {
        status = build_output(&options, &output);
    }
    if (status == 0) {
        status = write_output(&output);
    }

    free(output.data);
    string_list_free(&options.dictionary);
    string_list_free(&options.queries);
    return status;
}
