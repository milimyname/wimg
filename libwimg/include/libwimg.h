#ifndef LIBWIMG_H
#define LIBWIMG_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// All functions returning pointers return length-prefixed JSON strings:
// first 4 bytes = uint32_t length (little-endian), then the string data.
// Caller must call wimg_free() on the returned pointer when done.

// --- Lifecycle ---

// Initialize the database at the given path. Returns 0 on success, -1 on error.
int32_t wimg_init(const char *db_path);

// Close the database and free resources.
void wimg_close(void);

// Free a pointer previously returned by other wimg_ functions.
void wimg_free(const uint8_t *ptr, uint32_t len);

// Allocate memory in the wimg scratch space. Used by WASM host.
uint8_t *wimg_alloc(uint32_t size);

// Get the last error message (length-prefixed string), or NULL if no error.
const uint8_t *wimg_get_error(void);

// --- Import ---

// Parse a CSV file without importing (preview only). Auto-detects format.
// Returns pointer to length-prefixed JSON: {"format":"...","total_rows":N,"transactions":[...]}
// Each transaction: {"id":"...","date":"YYYY-MM-DD","description":"...","amount":X.XX,"currency":"EUR","category":N}
// Returns NULL on error.
const uint8_t *wimg_parse_csv(const uint8_t *data, uint32_t len);

// Import a CSV file. Auto-detects format (Comdirect, Trade Republic, Scalable).
// Returns pointer to length-prefixed JSON: {"total_rows":N,"imported":N,"skipped_duplicates":N,"errors":N,"format":"...","categorized":N}
// Returns NULL on error.
const uint8_t *wimg_import_csv(const uint8_t *data, uint32_t len);

// --- Transactions ---

// Get all transactions as a length-prefixed JSON array.
const uint8_t *wimg_get_transactions(void);

// Set the category for a transaction by ID. Returns 0 on success, -1 on error.
int32_t wimg_set_category(const uint8_t *id, uint32_t id_len, uint8_t category);

// Set the excluded flag for a transaction. excluded=1 hides from summaries, excluded=0 restores.
int32_t wimg_set_excluded(const uint8_t *id, uint32_t id_len, uint8_t excluded);

// Re-run auto-categorization on all uncategorized transactions.
// Returns number of newly categorized, or -1 on error.
int32_t wimg_auto_categorize(void);

// --- Summaries ---

// Get monthly summary as length-prefixed JSON.
// Returns: {"year":N,"month":N,"income":X,"expenses":X,"available":X,"tx_count":N,"by_category":[...]}
const uint8_t *wimg_get_summary(uint32_t year, uint32_t month);

// --- Debts ---

// Get all debts as a length-prefixed JSON array.
const uint8_t *wimg_get_debts(void);

// Add a debt. Input is JSON: {"id":"...","name":"...","total":N,"monthly":N}
// Amounts are decimal (e.g. 1234.56), converted to cents internally.
int32_t wimg_add_debt(const uint8_t *data, uint32_t len);

// Mark a debt as partially paid. amount_cents is in cents.
int32_t wimg_mark_debt_paid(const uint8_t *id, uint32_t id_len, int64_t amount_cents);

// Delete a debt by ID.
int32_t wimg_delete_debt(const uint8_t *id, uint32_t id_len);

// --- Accounts ---

// Get all accounts as a length-prefixed JSON array.
const uint8_t *wimg_get_accounts(void);

// Add an account. Input is JSON: {"id":"...","name":"...","color":"#..."}
int32_t wimg_add_account(const uint8_t *data, uint32_t len);

// Update an account. Input is JSON: {"id":"...","name":"...","color":"#..."}
int32_t wimg_update_account(const uint8_t *data, uint32_t len);

// Delete an account by ID.
int32_t wimg_delete_account(const uint8_t *id, uint32_t id_len);

// Get transactions filtered by account (empty string = all).
const uint8_t *wimg_get_transactions_filtered(const uint8_t *acct, uint32_t acct_len);

// Get summary filtered by account.
const uint8_t *wimg_get_summary_filtered(uint32_t year, uint32_t month, const uint8_t *acct, uint32_t acct_len);

// --- Categories ---

// Get all category metadata as a length-prefixed JSON array (static, no DB needed).
const uint8_t *wimg_get_categories(void);

// --- Undo/Redo ---

// Undo the last action. Returns length-prefixed JSON with undo info, or NULL.
const uint8_t *wimg_undo(void);

// Redo the last undone action. Returns length-prefixed JSON, or NULL.
const uint8_t *wimg_redo(void);

#ifdef __cplusplus
}
#endif

#endif // LIBWIMG_H
