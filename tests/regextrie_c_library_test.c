#include <assert.h>
#include <stddef.h>

#include "trie.h"

static size_t count_nodes(const Trie *trie) {
    size_t total = 1;
    size_t index;
    for (index = 0; index < trie->size; ++index) {
        total += count_nodes(trie->nodes[index]);
    }
    return total;
}

static void test_empty_and_plain_words(void) {
    Trie *trie = new_trie();
    char empty[] = "";
    char foo[] = "foo";
    char upper[] = "FOO";
    char alias[] = "&//";
    char wildcard[] = "?oo";
    char prefix[] = "fo";
    char suffix[] = "fooo";

    assert(find_word(trie, empty) == 0);
    assert(find_word(trie, foo) == 0);
    add_word(trie, empty);
    assert(find_word(trie, empty) == 1);
    add_word(trie, foo);
    add_word(trie, foo);
    assert(find_word(trie, foo) == 1);
    assert(find_word(trie, upper) == 1);
    assert(find_word(trie, alias) == 1);
    assert(find_word(trie, wildcard) == 0);
    assert(find_word(trie, prefix) == 0);
    assert(find_word(trie, suffix) == 0);
    free_trie(trie);
}

static void test_at_collision(void) {
    Trie *with_at = new_trie();
    Trie *without_at = new_trie();
    char a_at_b[] = "a@b";
    char ab[] = "ab";
    char a_at_at_b[] = "a@@b";

    add_word(with_at, a_at_b);
    assert(find_word(with_at, a_at_b) == 1);
    assert(find_word(with_at, ab) == 1);
    assert(find_word(with_at, a_at_at_b) == 1);

    add_word(without_at, ab);
    assert(find_word(without_at, ab) == 1);
    assert(find_word(without_at, a_at_b) == 0);
    free_trie(with_at);
    free_trie(without_at);
}

static void test_regex_expansion(void) {
    Trie *trie = new_trie();
    char source[] = "foo";
    char combinations[][4] = {"foo", "?oo", "f?o", "fo?", "??o", "?o?", "f??", "???"};
    char underscore[] = "_oo";
    char missing[] = "bar";
    char short_query[] = "fo";
    char long_query[] = "fooo";
    size_t index;

    add_regex(trie, source);
    for (index = 0; index < sizeof(combinations) / sizeof(combinations[0]); ++index) {
        assert(find_word(trie, combinations[index]) == 1);
    }
    assert(find_word(trie, underscore) == 1);
    assert(find_word(trie, missing) == 0);
    assert(find_word(trie, short_query) == 0);
    assert(find_word(trie, long_query) == 0);
    free_trie(trie);
}

static void test_exponential_tree_shape(void) {
    Trie *trie = new_trie();
    char source[] = "abcdefghij";
    add_regex(trie, source);
    assert(count_nodes(trie) == 2047);
    free_trie(trie);
}

int main(void) {
    assert(find_word(NULL, "anything") == 0);
    test_empty_and_plain_words();
    test_at_collision();
    test_regex_expansion();
    test_exponential_tree_shape();
    return 0;
}
