/* Stillroom's vault engine for Windows: the C interface. Generated from src/ffi.rs by tests/header.rs;
   don't edit by hand. Every call returns a StillroomStatus (0: done); stillroom_last_error() says why not. */

#ifndef STILLROOM_H
#define STILLROOM_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/**
 * The interface's version: raised when a function changes, so an app built against another can tell.
 */
#define STILLROOM_ABI_VERSION 1

/**
 * A chunked item read a range at a time, straight from its sealed file, for a player. Holds its own copy of the
 * item's key (in locked memory) until freed.
 */
typedef struct StillroomReader StillroomReader;

/**
 * A vault folder. Opaque to the app.
 */
typedef struct StillroomStore StillroomStore;

/**
 * One slot unlocked. Opaque to the app; freeing it is locking.
 */
typedef struct StillroomVault StillroomVault;

/**
 * Bytes the engine hands out: contents of an item, an attachment. Freed (and wiped) with `stillroom_bytes_free`.
 */
typedef struct StillroomBytes {
  uint8_t *data;
  size_t length;
} StillroomBytes;

/**
 * What a call did: 0 for done, otherwise why not.
 */
typedef int32_t StillroomStatus;

/**
 * Reads the text of what only the app can (a PDF, the words in a picture): given the item (JSON) and its contents,
 * returns UTF-8 text, or null for none. What it returns must stay valid until it's called again or the refresh ends.
 */
typedef const char *(*StillroomReadText)(void *context,
                                         const char *item,
                                         const uint8_t *data,
                                         size_t length);

#define STILLROOM_OK 0

#define STILLROOM_WRONG_PASSWORD 1

#define STILLROOM_WRONG_RECOVERY_KEY 2

#define STILLROOM_DAMAGED 3

#define STILLROOM_FOLDER 4

#define STILLROOM_HELLO_UNAVAILABLE 5

#define STILLROOM_HELLO_CHANGED 6

#define STILLROOM_NOT_THIS_COMPUTER 7

#define STILLROOM_SAME_AS_OTHER 8

#define STILLROOM_WRONG_KIT 9

#define STILLROOM_NEWER_VAULT 10

#define STILLROOM_TOO_SOON 11

#define STILLROOM_KIT_MISTYPED 20

#define STILLROOM_KIT_MIXED 21

#define STILLROOM_KIT_NOT_ENOUGH 22

#define STILLROOM_DISK 30

#define STILLROOM_READ_ONLY 31

#define STILLROOM_NOT_FOUND 32

#define STILLROOM_FOLDER_EXISTS 33

#define STILLROOM_FOLDER_INTO_ITSELF 34

#define STILLROOM_NOT_A_BACKUP 35

#define STILLROOM_NOT_AN_EXPORT 36

#define STILLROOM_LOCKED_ELSEWHERE 37

#define STILLROOM_NO_TPM 38

#define STILLROOM_INVALID_ARGUMENT 40

#define STILLROOM_PANICKED 41

#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

/**
 * The words for the last failure on this thread. Valid until the next call on this thread.
 */
const char *stillroom_last_error(void);

uint32_t stillroom_abi_version(void);

/**
 * Wipes and frees a string the engine gave (a recovery key and kit pieces are among them). Null is fine.
 */
void stillroom_string_free(char *value);

/**
 * Wipes and frees bytes the engine gave. An empty or null one is fine.
 */
void stillroom_bytes_free(struct StillroomBytes value);

/**
 * Whether every key is kept in locked memory, out of the page file. False means Windows refused: worth telling.
 */
bool stillroom_keys_are_locked(void);

/**
 * Keeps this program out of Windows Error Reporting, so a crash never writes its memory to disk. Call once at start.
 */
StillroomStatus stillroom_exclude_from_crash_reports(void);

/**
 * Turns on Windows' process protections (`platform.rs`): no extension DLLs (keyboard-hook injection; also IMEs, so
 * `block_extension_dlls` is a setting), no images from the network or low-integrity files, invalid handles fatal.
 * Can't be undone; call once, early. Gives what took, as bits: 1 extension DLLs, 2 image loads, 4 strict handles.
 */
StillroomStatus stillroom_harden_process(bool block_extension_dlls,
                                         uint32_t *hardened);

/**
 * A folder made (if need be) and readable by this account only, as the vault folder is: for Edit in Place's working
 * copies. Its permissions are replaced by one entry, this account's, inherited by everything inside.
 */
StillroomStatus stillroom_protect_folder(const char *folder);

/**
 * Whether this PC has a TPM the vault can be locked to.
 */
bool stillroom_tpm_available(void);

/**
 * Asks for a secret on a desktop of its own, where other programs' keyboard hooks can't see it: the screen switches to
 * a small prompt and back. `multiline` for kit pieces (a piece per line, shown as typed); otherwise one line, hidden.
 * Gives what was typed (wipe it: free it with `stillroom_bytes_free`), or `cancelled` true (Cancel, Escape, or two
 * minutes untouched).
 */
StillroomStatus stillroom_secure_prompt(const char *title,
                                        const char *message,
                                        bool multiline,
                                        struct StillroomBytes *typed,
                                        bool *cancelled);

/**
 * 32 random bytes for Windows Hello to sign, to turn it on (`stillroom_vault_turn_on_hello`).
 */
StillroomStatus stillroom_hello_new_challenge(struct StillroomBytes *result);

/**
 * Opens the vault folder at `root` (UTF-8), or the usual one (%APPDATA%\Stillroom\Store) when it's null. Nothing is
 * read or made yet. `read_only` opens it only to take things out: nothing is tidied or written.
 */
StillroomStatus stillroom_store_open(const char *root,
                                     bool read_only,
                                     struct StillroomStore **result);

/**
 * For tests only: passwords stretched at a low cost from now on in this store, as the Mac's tests lower it.
 */
StillroomStatus stillroom_store_lower_cost_for_tests(struct StillroomStore *handle);

void stillroom_store_free(struct StillroomStore *handle);

/**
 * Whether a vault is there (both slots' password keys are).
 */
StillroomStatus stillroom_store_exists(const struct StillroomStore *handle, bool *result);

/**
 * A folder from before format 4: never read, and nothing is written over it.
 */
StillroomStatus stillroom_store_is_old_format(const struct StillroomStore *handle, bool *result);

/**
 * Locked to the Mac that made it: only the recovery key or the kit opens it here.
 */
StillroomStatus stillroom_store_is_locked_to_a_mac(const struct StillroomStore *handle,
                                                   bool *result);

/**
 * A new vault with this password. Gives the open vault and its recovery key, to be shown once.
 */
StillroomStatus stillroom_store_create(const struct StillroomStore *handle,
                                       const uint8_t *password,
                                       size_t password_length,
                                       struct StillroomVault **vault,
                                       char **recovery_key);

StillroomStatus stillroom_store_unlock_with_password(const struct StillroomStore *handle,
                                                     const uint8_t *password,
                                                     size_t password_length,
                                                     struct StillroomVault **vault);

/**
 * Locked to a PC: here if this is the PC (the password opens it), elsewhere only the recovery key or the kit.
 */
StillroomStatus stillroom_store_is_locked_to_a_pc(const struct StillroomStore *handle,
                                                  bool *result);

/**
 * The challenge to ask Windows Hello to sign at the lock screen. `STILLROOM_NOT_FOUND` when Hello isn't on.
 */
StillroomStatus stillroom_store_hello_challenge(const struct StillroomStore *handle,
                                                struct StillroomBytes *result);

/**
 * Windows Hello's signature of the challenge opens the vault that turned Hello on. `STILLROOM_HELLO_CHANGED` when it
 * opens nothing (Hello was set up again): use the password, then turn Hello on again.
 */
StillroomStatus stillroom_store_unlock_with_hello(const struct StillroomStore *handle,
                                                  const uint8_t *signature,
                                                  size_t signature_length,
                                                  struct StillroomVault **vault);

/**
 * Any case, with or without dashes and spaces. A new password must be set before anything else.
 */
StillroomStatus stillroom_store_unlock_with_recovery_key(const struct StillroomStore *handle,
                                                         const uint8_t *recovery_key,
                                                         size_t recovery_key_length,
                                                         struct StillroomVault **vault);

/**
 * Kit pieces as typed, one per line. A new password must be set before anything else.
 */
StillroomStatus stillroom_store_unlock_with_kit(const struct StillroomStore *handle,
                                                const uint8_t *pieces,
                                                size_t pieces_length,
                                                struct StillroomVault **vault);

/**
 * A wrong try at the lock screen, for both slots' intruder logs: `kind` 0 for a password, 1 for a recovery key. What
 * was typed is never kept. `photo` (a JPEG) may be empty.
 */
StillroomStatus stillroom_store_record_intruder(const struct StillroomStore *handle,
                                                int32_t kind,
                                                const uint8_t *photo,
                                                size_t photo_length);

/**
 * Seconds to wait before the next try at the lock screen (0: now).
 */
StillroomStatus stillroom_store_wait_before_next_try(const struct StillroomStore *handle,
                                                     uint64_t *seconds);

/**
 * A wrong password, recovery key or kit at the lock screen (not a vault locked to a Mac, which isn't a guess).
 */
StillroomStatus stillroom_store_count_wrong_try(const struct StillroomStore *handle);

/**
 * A good try at the lock screen: the wait goes.
 */
StillroomStatus stillroom_store_clear_wrong_tries(const struct StillroomStore *handle);

/**
 * A backup of the vault while it's locked, into one file at `to` (UTF-8 path).
 */
StillroomStatus stillroom_store_backup(const struct StillroomStore *handle, const char *to);

/**
 * Puts the vault back from a backup. Gives where the vault it replaced was set aside, or null when there was none.
 * Lock the vault (free its handle) first.
 */
StillroomStatus stillroom_store_restore(const struct StillroomStore *handle,
                                        const char *file,
                                        char **set_aside);

/**
 * Whether a file is a Stillroom backup, without touching the vault.
 */
StillroomStatus stillroom_backup_check(const char *file);

/**
 * Locks: the keys and everything decrypted are wiped. Null is fine.
 */
void stillroom_vault_lock(struct StillroomVault *handle);

/**
 * Everything the window shows, as JSON: `{"files": [item…], "folders": […], "tags": […], "showInCapture",
 * "hasKit", "kitMade", "mustSetPassword", "intruderWasReset", "intruders", "lockedToAPc", "helloIsMine"}`. An item is as the list keeps it
 * (`id`, `name`, `uti`, `size`, `addedAt`, `folder`, `modifiedAt`, `tags`, `entry`, `versions`, `chunked`, `created`,
 * `contentModified`…), never with a key. Dates are seconds since 2001.
 */
StillroomStatus stillroom_vault_state(const struct StillroomVault *handle,
                                      char **result);

/**
 * Adds files and folders (a JSON array of paths) into `folder` (or the top, when null). Gives JSON:
 * `{"items": [id…], "originals": {"files": […], "folders": […]}, "unchecked": [path…], "failed": [{"path",
 * "code", "message"}…], "skipped": n}`. Only `originals` may be deleted (`stillroom_delete_originals`).
 */
StillroomStatus stillroom_vault_add(const struct StillroomVault *handle,
                                    const char *paths,
                                    const char *folder,
                                    char **result);

/**
 * Deletes for good the originals an add checked (`{"files": […], "folders": […]}` as `stillroom_vault_add` gave
 * them): folders whole only when everything in them went in. Gives a JSON array of the names that couldn't be.
 */
StillroomStatus stillroom_delete_originals(const char *originals,
                                           char **result);

/**
 * What deleting the originals would remove, as a JSON array of paths: folders whole only when everything in them
 * went in, else their checked files one by one. For moving them to the Recycle Bin instead, by the same rule.
 */
StillroomStatus stillroom_originals_removals(const char *originals,
                                             char **result);

/**
 * Bytes held only in memory (an email's attachment) sealed in as a file named `name`, in `folder` (or the top).
 */
StillroomStatus stillroom_vault_add_data(const struct StillroomVault *handle,
                                         const uint8_t *data,
                                         size_t length,
                                         const char *name,
                                         const char *folder,
                                         char **result);

/**
 * A new note (`kind` 0, Markdown) or secret (`kind` 1, JSON), in `folder` (or the top). Gives its id.
 */
StillroomStatus stillroom_vault_new_entry(const struct StillroomVault *handle,
                                          int32_t kind,
                                          const char *name,
                                          const uint8_t *content,
                                          size_t content_length,
                                          const char *folder,
                                          char **result);

/**
 * An item's current contents, or (when `version` isn't null) one of its earlier versions.
 */
StillroomStatus stillroom_vault_read(const struct StillroomVault *handle,
                                     const char *item,
                                     const char *version,
                                     struct StillroomBytes *result);

/**
 * An item written out to `to` (a copy the person saves, or a working copy), with its dates, marked as downloaded.
 */
StillroomStatus stillroom_vault_export_item(const struct StillroomVault *handle,
                                            const char *item,
                                            const char *to);

/**
 * Everything out, unencrypted, in a new folder "Stillroom Export <date>" inside `parent`. Gives JSON: `{"folder",
 * "taken", "failed": [{"path", "message"}…]}`.
 */
StillroomStatus stillroom_vault_export_all(const struct StillroomVault *handle,
                                           const char *parent,
                                           char **result);

StillroomStatus stillroom_vault_delete(const struct StillroomVault *handle, const char *item);

/**
 * New contents for an item, from memory, and a new name when `name` isn't null. What it held is kept as a version
 * when it hadn't changed for ten minutes.
 */
StillroomStatus stillroom_vault_update(const struct StillroomVault *handle,
                                       const char *item,
                                       const uint8_t *data,
                                       size_t length,
                                       const char *name);

/**
 * New contents for an item from a file on disk (a save from editing in place): big ones go in chunks.
 */
StillroomStatus stillroom_vault_update_from_file(const struct StillroomVault *handle,
                                                 const char *item,
                                                 const char *file);

StillroomStatus stillroom_vault_restore_version(const struct StillroomVault *handle,
                                                const char *item,
                                                const char *version);

StillroomStatus stillroom_vault_drop_version(const struct StillroomVault *handle,
                                             const char *item,
                                             const char *version);

/**
 * Damaged current contents swapped for an earlier version that still opens.
 */
StillroomStatus stillroom_vault_fall_back(const struct StillroomVault *handle,
                                          const char *item,
                                          const char *version);

/**
 * Reads every item and version through. Gives a JSON array of what doesn't open: `[{"item", "version",
 * "fallback"}…]` (`version` null for current contents; `fallback` the newest version that still opens).
 */
StillroomStatus stillroom_vault_check(const struct StillroomVault *handle,
                                      char **result);

StillroomStatus stillroom_vault_rename(const struct StillroomVault *handle,
                                       const char *item,
                                       const char *name);

/**
 * `tags`: a JSON array of strings (empty: none).
 */
StillroomStatus stillroom_vault_set_tags(const struct StillroomVault *handle,
                                         const char *item,
                                         const char *tags);

/**
 * A folder made in `parent` (or the top). A "/" typed in the name is kept as a look-alike.
 */
StillroomStatus stillroom_vault_make_folder(const struct StillroomVault *handle,
                                            const char *name,
                                            const char *parent);

/**
 * Items (a JSON array of ids) into `folder` (or the top).
 */
StillroomStatus stillroom_vault_move_items(const struct StillroomVault *handle,
                                           const char *items,
                                           const char *folder);

/**
 * Renames a folder, carrying everything inside it along. Gives its new path, or null when nothing changed.
 */
StillroomStatus stillroom_vault_rename_folder(const struct StillroomVault *handle,
                                              const char *folder,
                                              const char *name,
                                              char **result);

/**
 * A folder, with everything in it, into another (or the top, when `into` is null).
 */
StillroomStatus stillroom_vault_move_folder(const struct StillroomVault *handle,
                                            const char *folder,
                                            const char *into);

/**
 * A folder and everything inside it, versions too, deleted.
 */
StillroomStatus stillroom_vault_delete_folder(const struct StillroomVault *handle,
                                              const char *folder);

/**
 * Shown in screenshots and screen sharing while open: kept sealed in the vault.
 */
StillroomStatus stillroom_vault_set_show_in_capture(const struct StillroomVault *handle, bool on);

StillroomStatus stillroom_vault_change_password(const struct StillroomVault *handle,
                                                const uint8_t *current,
                                                size_t current_length,
                                                const uint8_t *new_,
                                                size_t new_length);

/**
 * After a recovery key or the kit: the new password.
 */
StillroomStatus stillroom_vault_set_password_after_recovery(const struct StillroomVault *handle,
                                                            const uint8_t *new_,
                                                            size_t new_length);

/**
 * A decoy password: the other slot becomes a new, empty vault it opens. Gives that vault's recovery key, to be shown
 * once.
 */
StillroomStatus stillroom_vault_set_other_slot(const struct StillroomVault *handle,
                                               const uint8_t *password,
                                               size_t password_length,
                                               char **recovery_key);

/**
 * No decoy: the other slot becomes one whose passwords nobody knows.
 */
StillroomStatus stillroom_vault_reset_other_slot(const struct StillroomVault *handle);

/**
 * A new recovery key for the open vault, to be shown once; the old one stops working.
 */
StillroomStatus stillroom_vault_new_recovery_key(const struct StillroomVault *handle,
                                                 char **recovery_key);

/**
 * A new emergency kit: `count` pieces, any `threshold` of which open this vault. Gives the pieces as a JSON array of
 * strings, to be printed once. Any earlier kit stops working.
 */
StillroomStatus stillroom_vault_make_kit(const struct StillroomVault *handle,
                                         uint8_t threshold,
                                         uint8_t count,
                                         char **pieces);

StillroomStatus stillroom_vault_remove_kit(const struct StillroomVault *handle);

/**
 * Whether to say, now, that the kit is a year old (it's then remembered as said).
 */
StillroomStatus stillroom_vault_kit_reminder_due(const struct StillroomVault *handle, bool *result);

/**
 * Locks both vaults' password keys to this PC's TPM. Gives a new recovery key for this vault, to be shown once (null
 * when it was already locked). `STILLROOM_LOCKED_ELSEWHERE` when it's locked to a Mac; `STILLROOM_NO_TPM` without one.
 */
StillroomStatus stillroom_vault_lock_to_this_pc(const struct StillroomVault *handle,
                                                char **recovery_key);

/**
 * The lock off: both password keys back as they were, and the TPM key deleted.
 */
StillroomStatus stillroom_vault_unlock_from_this_pc(const struct StillroomVault *handle);

/**
 * Windows Hello opens this vault from now on: the challenge (from `stillroom_hello_new_challenge`), Windows Hello's
 * signature of it, and the credential's public key. Wipe the signature afterwards: it opens the vault.
 */
StillroomStatus stillroom_vault_turn_on_hello(const struct StillroomVault *handle,
                                              const uint8_t *challenge,
                                              size_t challenge_length,
                                              const uint8_t *signature,
                                              size_t signature_length,
                                              const uint8_t *public_key,
                                              size_t public_key_length);

StillroomStatus stillroom_vault_turn_off_hello(const struct StillroomVault *handle);

/**
 * The intruder log, newest first, as JSON: `[{"id", "date", "kind": "wrongPassword"|"wrongRecoveryKey", "photo":
 * base64 JPEG or null}…]`.
 */
StillroomStatus stillroom_vault_intruders(const struct StillroomVault *handle,
                                          char **result);

StillroomStatus stillroom_vault_delete_intruder(const struct StillroomVault *handle,
                                                const char *entry);

StillroomStatus stillroom_vault_clear_intruders(const struct StillroomVault *handle);

/**
 * Reads every item whose words aren't known or have changed, and seals the index. `read_text` (may be null) reads
 * PDFs and pictures. Gives whether anything changed.
 */
StillroomStatus stillroom_vault_refresh_search(const struct StillroomVault *handle,
                                               StillroomReadText read_text,
                                               void *context,
                                               bool *changed);

/**
 * Items whose name, tags or words hold `query`: a JSON array of ids.
 */
StillroomStatus stillroom_vault_search(const struct StillroomVault *handle,
                                       const char *query,
                                       char **result);

/**
 * A piece of an item's words around `query`, or null.
 */
StillroomStatus stillroom_vault_snippet(const struct StillroomVault *handle,
                                        const char *item,
                                        const char *query,
                                        char **result);

/**
 * Accounts from a password export (CSV bytes), each a Login secret in "Imported". Gives JSON `{"added", "skipped"}`.
 */
StillroomStatus stillroom_vault_import_logins(const struct StillroomVault *handle,
                                              const uint8_t *csv,
                                              size_t csv_length,
                                              char **result);

/**
 * A backup of the open vault into one file at `to`. No save can land while it's made.
 */
StillroomStatus stillroom_vault_backup(const struct StillroomVault *handle, const char *to);

/**
 * Puts the vault back from a backup. The vault is locked first, so its handle is freed whatever happens. Gives where
 * the vault it replaced was set aside, or null.
 */
StillroomStatus stillroom_vault_restore_backup(struct StillroomVault *handle,
                                               const char *file,
                                               char **set_aside);

/**
 * The vault and every file in it, for good. Its handle is freed whatever happens.
 */
StillroomStatus stillroom_vault_wipe(struct StillroomVault *handle);

/**
 * A reader for an item sealed in chunks (all audio and video, and anything over 8 MiB). Gives its real size.
 */
StillroomStatus stillroom_vault_open_reader(const struct StillroomVault *handle,
                                            const char *item,
                                            struct StillroomReader **reader,
                                            uint64_t *size);

/**
 * Up to `capacity` bytes from `offset` into `buffer`; gives how many (fewer at the end, 0 past it).
 */
StillroomStatus stillroom_reader_read(const struct StillroomReader *reader,
                                      uint64_t offset,
                                      uint8_t *buffer,
                                      size_t capacity,
                                      size_t *read);

void stillroom_reader_free(struct StillroomReader *reader);

/**
 * How many bits a guesser would need for this password, roughly; 50 is enough.
 */
StillroomStatus stillroom_password_strength(const uint8_t *password,
                                            size_t password_length,
                                            double *bits,
                                            bool *enough);

/**
 * The two-factor code a secret's field shows (an otpauth link, or a setup key under a label that says so), at
 * `unix_seconds`. Gives null when the field holds none.
 */
StillroomStatus stillroom_one_time_code(const char *label,
                                        const uint8_t *value,
                                        size_t value_length,
                                        double unix_seconds,
                                        char **code,
                                        uint64_t *seconds_left);

/**
 * The UTI a file named `name` gets (as the Mac names kinds).
 */
StillroomStatus stillroom_uti_for_name(const char *name, char **result);

/**
 * How a kind looks, for its symbol and its shelf: 0 other, 1 picture, 2 audio, 3 video, 4 PDF, 5 text, 6 document
 * (office files), 7 archive. Pictures go on Images; audio and video on Audio & Video; PDFs, text and documents on
 * Documents; the rest on Other.
 */
StillroomStatus stillroom_look(const char *uti,
                               uint8_t *result);

/**
 * Whether an item may be opened in another app: documents, pictures, PDFs, audio and video only.
 */
StillroomStatus stillroom_can_edit(const char *uti, const char *name, bool is_file, bool *result);

/**
 * An email (.eml or .emlx bytes) read into JSON: `{"from", "to", "cc", "subject", "date", "page", "text",
 * "attachments": [{"name", "kind", "size"}…]}`. `page` is the HTML to show; nothing in it may be fetched. Gives null
 * when the bytes aren't an email.
 */
StillroomStatus stillroom_email_read(const uint8_t *data,
                                     size_t length,
                                     char **result);

/**
 * One of an email's attachments, by its place in `attachments`.
 */
StillroomStatus stillroom_email_attachment(const uint8_t *data,
                                           size_t length,
                                           size_t index,
                                           struct StillroomBytes *result);

#ifdef __cplusplus
}  // extern "C"
#endif  // __cplusplus

#endif  /* STILLROOM_H */
