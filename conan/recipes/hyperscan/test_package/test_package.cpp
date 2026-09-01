#include <hs/hs.h>

#include <cstring>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace {

void require(bool condition, const char *message) {
    if (!condition) {
        throw std::runtime_error(message);
    }
}

int on_match(unsigned id, unsigned long long, unsigned long long to, unsigned,
             void *context) {
    std::vector<std::pair<unsigned, unsigned long long> > *matches =
        static_cast<std::vector<std::pair<unsigned, unsigned long long> > *>(context);
    matches->push_back(std::make_pair(id, to));
    return 0;
}

} // namespace

int main() {
    static_assert(HS_MAJOR == 5, "unexpected Hyperscan major version");
    static_assert(HS_MINOR == 4, "unexpected Hyperscan minor version");
    static_assert(HS_PATCH == 2, "unexpected Hyperscan patch version");
    require(std::string(REGEX_UTILS_HYPERSCAN_PACKAGE_VERSION) == "5.4.2.1",
            "unexpected package version");
    require(hs_valid_platform() == HS_SUCCESS, "unsupported runtime platform");

    const char *expressions[] = {"foo", "b\\x00r"};
    const unsigned flags[] = {0, 0};
    const unsigned ids[] = {1, 2};
    hs_database_t *database = NULL;
    hs_compile_error_t *compile_error = NULL;
    require(hs_compile_multi(expressions, flags, ids, 2, HS_MODE_BLOCK, NULL,
                             &database, &compile_error) == HS_SUCCESS,
            "pattern compilation failed");
    require(compile_error == NULL, "unexpected compile diagnostic");

    hs_scratch_t *scratch = NULL;
    require(hs_alloc_scratch(database, &scratch) == HS_SUCCESS,
            "scratch allocation failed");
    const char subject[] = {'x', 'f', 'o', 'o', 'b', '\0', 'r'};
    std::vector<std::pair<unsigned, unsigned long long> > matches;
    require(hs_scan(database, subject, sizeof(subject), 0, scratch, on_match,
                    &matches) == HS_SUCCESS,
            "subject scan failed");
    require(matches.size() == 2, "unexpected match count");
    require(matches[0] == std::make_pair(1U, 4ULL),
            "unexpected first match");
    require(matches[1] == std::make_pair(2U, 7ULL),
            "unexpected second match");

    require(hs_free_scratch(scratch) == HS_SUCCESS, "scratch cleanup failed");
    require(hs_free_database(database) == HS_SUCCESS, "database cleanup failed");
    return 0;
}
