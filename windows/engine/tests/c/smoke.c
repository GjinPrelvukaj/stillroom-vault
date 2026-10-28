/* The C interface from C: built by tests/c_abi.rs with MSVC against include/stillroom.h and the engine's DLL, then run
   with a fresh folder as its argument. Prints "ok" when every check passes. */

#include <stdio.h>
#include <string.h>

#include "stillroom.h"

#define CHECK(condition)                                                                       \
    do {                                                                                       \
        if (!(condition)) {                                                                    \
            printf("failed at line %d: %s (%s)\n", __LINE__, #condition, stillroom_last_error()); \
            return 1;                                                                          \
        }                                                                                      \
    } while (0)

int main(int argc, char **argv) {
    if (argc < 2) return 2;
    CHECK(stillroom_abi_version() == STILLROOM_ABI_VERSION);

    StillroomStore *store = NULL;
    CHECK(stillroom_store_open(argv[1], false, &store) == STILLROOM_OK);
    CHECK(stillroom_store_lower_cost_for_tests(store) == STILLROOM_OK);

    const char *password = "a password typed in C";
    StillroomVault *vault = NULL;
    char *recovery = NULL;
    CHECK(stillroom_store_create(store, (const uint8_t *)password, strlen(password), &vault, &recovery) == STILLROOM_OK);
    CHECK(strlen(recovery) == 29);
    stillroom_string_free(recovery);

    char *id = NULL;
    const char *text = "written from C";
    CHECK(stillroom_vault_new_entry(vault, 0, "From C", (const uint8_t *)text, strlen(text), NULL, &id) == STILLROOM_OK);

    StillroomBytes contents = {0};
    CHECK(stillroom_vault_read(vault, id, NULL, &contents) == STILLROOM_OK);
    CHECK(contents.length == strlen(text) && memcmp(contents.data, text, contents.length) == 0);
    stillroom_bytes_free(contents);

    char *state = NULL;
    CHECK(stillroom_vault_state(vault, &state) == STILLROOM_OK);
    CHECK(strstr(state, "\"From C\"") != NULL);
    stillroom_string_free(state);
    stillroom_string_free(id);
    stillroom_vault_lock(vault);
    vault = NULL;

    const char *wrong = "not it";
    CHECK(stillroom_store_unlock_with_password(store, (const uint8_t *)wrong, strlen(wrong), &vault) == STILLROOM_WRONG_PASSWORD);
    CHECK(strcmp(stillroom_last_error(), "That password doesn't open this vault.") == 0);
    CHECK(stillroom_store_unlock_with_password(store, (const uint8_t *)password, strlen(password), &vault) == STILLROOM_OK);

    double bits = 0;
    bool enough = true;
    CHECK(stillroom_password_strength((const uint8_t *)"Password123", 11, &bits, &enough) == STILLROOM_OK);
    CHECK(!enough);
    CHECK(stillroom_keys_are_locked());

    CHECK(stillroom_vault_wipe(vault) == STILLROOM_OK);
    stillroom_store_free(store);
    printf("ok\n");
    return 0;
}
