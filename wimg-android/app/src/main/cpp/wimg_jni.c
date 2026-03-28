#include <jni.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

// libwimg C ABI declarations (matches libwimg.h)
extern int32_t wimg_init(const char *db_path);
extern void wimg_close(void);
extern void wimg_free(const uint8_t *ptr, uint32_t len);
extern const uint8_t *wimg_get_error(void);
extern const uint8_t *wimg_get_transactions(void);
extern const uint8_t *wimg_get_transactions_filtered(const uint8_t *acct, uint32_t acct_len);
extern int32_t wimg_set_category(const uint8_t *id, uint32_t id_len, uint8_t category);
extern int32_t wimg_set_excluded(const uint8_t *id, uint32_t id_len, uint8_t excluded);
extern int32_t wimg_auto_categorize(void);
extern const uint8_t *wimg_get_summary(uint32_t year, uint32_t month);
extern const uint8_t *wimg_get_summary_filtered(uint32_t year, uint32_t month, const uint8_t *acct, uint32_t acct_len);
extern const uint8_t *wimg_parse_csv(const uint8_t *data, uint32_t len);
extern const uint8_t *wimg_import_csv(const uint8_t *data, uint32_t len);
extern const uint8_t *wimg_get_accounts(void);
extern const uint8_t *wimg_get_recurring(void);
extern int32_t wimg_detect_recurring(void);
extern int32_t wimg_take_snapshot(uint32_t year, uint32_t month);
extern const uint8_t *wimg_get_snapshots(void);
extern const uint8_t *wimg_undo(void);
extern const uint8_t *wimg_redo(void);
extern const uint8_t *wimg_get_debts(void);
extern int32_t wimg_add_debt(const uint8_t *data, uint32_t len);
extern int32_t wimg_mark_debt_paid(const uint8_t *id, uint32_t id_len, int64_t amount_cents);
extern int32_t wimg_delete_debt(const uint8_t *id, uint32_t id_len);
extern const uint8_t *wimg_get_goals(void);
extern int32_t wimg_add_goal(const uint8_t *data, uint32_t len);
extern int32_t wimg_contribute_goal(const uint8_t *id, uint32_t id_len, int64_t amount_cents);
extern int32_t wimg_delete_goal(const uint8_t *id, uint32_t id_len);
extern const uint8_t *wimg_export_csv(void);
extern const uint8_t *wimg_export_db(void);

// Helper: read 4-byte LE length-prefixed data and create a Java string, then free
static jstring ptr_to_jstring(JNIEnv *env, const uint8_t *ptr) {
    if (!ptr) return NULL;
    uint32_t len = ptr[0] | (ptr[1] << 8) | (ptr[2] << 16) | (ptr[3] << 24);
    if (len == 0) { wimg_free(ptr, 0); return NULL; }
    // Create a null-terminated copy for NewStringUTF
    char *buf = malloc(len + 1);
    memcpy(buf, ptr + 4, len);
    buf[len] = '\0';
    wimg_free(ptr, 0);
    jstring result = (*env)->NewStringUTF(env, buf);
    free(buf);
    return result;
}

#define JNI_FN(name) Java_com_wimg_app_bridge_WimgJni_##name

// --- Lifecycle ---

JNIEXPORT jint JNICALL JNI_FN(nativeInit)(JNIEnv *env, jobject obj, jstring path) {
    const char *db_path = (*env)->GetStringUTFChars(env, path, NULL);
    int32_t rc = wimg_init(db_path);
    (*env)->ReleaseStringUTFChars(env, path, db_path);
    return rc;
}

JNIEXPORT void JNICALL JNI_FN(nativeClose)(JNIEnv *env, jobject obj) {
    wimg_close();
}

JNIEXPORT jstring JNICALL JNI_FN(nativeGetError)(JNIEnv *env, jobject obj) {
    return ptr_to_jstring(env, wimg_get_error());
}

// --- Transactions ---

JNIEXPORT jstring JNICALL JNI_FN(nativeGetTransactions)(JNIEnv *env, jobject obj) {
    return ptr_to_jstring(env, wimg_get_transactions());
}

JNIEXPORT jstring JNICALL JNI_FN(nativeGetTransactionsFiltered)(JNIEnv *env, jobject obj, jstring acct) {
    const char *a = (*env)->GetStringUTFChars(env, acct, NULL);
    jsize alen = (*env)->GetStringUTFLength(env, acct);
    const uint8_t *ptr = wimg_get_transactions_filtered((const uint8_t *)a, alen);
    (*env)->ReleaseStringUTFChars(env, acct, a);
    return ptr_to_jstring(env, ptr);
}

JNIEXPORT jint JNICALL JNI_FN(nativeSetCategory)(JNIEnv *env, jobject obj, jstring id, jint category) {
    const char *cid = (*env)->GetStringUTFChars(env, id, NULL);
    jsize len = (*env)->GetStringUTFLength(env, id);
    int32_t rc = wimg_set_category((const uint8_t *)cid, len, (uint8_t)category);
    (*env)->ReleaseStringUTFChars(env, id, cid);
    return rc;
}

JNIEXPORT jint JNICALL JNI_FN(nativeSetExcluded)(JNIEnv *env, jobject obj, jstring id, jint excluded) {
    const char *cid = (*env)->GetStringUTFChars(env, id, NULL);
    jsize len = (*env)->GetStringUTFLength(env, id);
    int32_t rc = wimg_set_excluded((const uint8_t *)cid, len, (uint8_t)excluded);
    (*env)->ReleaseStringUTFChars(env, id, cid);
    return rc;
}

JNIEXPORT jint JNICALL JNI_FN(nativeAutoCategorize)(JNIEnv *env, jobject obj) {
    return wimg_auto_categorize();
}

// --- Summaries ---

JNIEXPORT jstring JNICALL JNI_FN(nativeGetSummary)(JNIEnv *env, jobject obj, jint year, jint month) {
    return ptr_to_jstring(env, wimg_get_summary(year, month));
}

JNIEXPORT jstring JNICALL JNI_FN(nativeGetSummaryFiltered)(JNIEnv *env, jobject obj, jint year, jint month, jstring acct) {
    const char *a = (*env)->GetStringUTFChars(env, acct, NULL);
    jsize alen = (*env)->GetStringUTFLength(env, acct);
    const uint8_t *ptr = wimg_get_summary_filtered(year, month, (const uint8_t *)a, alen);
    (*env)->ReleaseStringUTFChars(env, acct, a);
    return ptr_to_jstring(env, ptr);
}

// --- Import ---

JNIEXPORT jstring JNICALL JNI_FN(nativeParseCsv)(JNIEnv *env, jobject obj, jbyteArray data) {
    jsize len = (*env)->GetArrayLength(env, data);
    jbyte *bytes = (*env)->GetByteArrayElements(env, data, NULL);
    const uint8_t *ptr = wimg_parse_csv((const uint8_t *)bytes, len);
    (*env)->ReleaseByteArrayElements(env, data, bytes, JNI_ABORT);
    return ptr_to_jstring(env, ptr);
}

JNIEXPORT jstring JNICALL JNI_FN(nativeImportCsv)(JNIEnv *env, jobject obj, jbyteArray data) {
    jsize len = (*env)->GetArrayLength(env, data);
    jbyte *bytes = (*env)->GetByteArrayElements(env, data, NULL);
    const uint8_t *ptr = wimg_import_csv((const uint8_t *)bytes, len);
    (*env)->ReleaseByteArrayElements(env, data, bytes, JNI_ABORT);
    return ptr_to_jstring(env, ptr);
}

// --- Accounts ---

JNIEXPORT jstring JNICALL JNI_FN(nativeGetAccounts)(JNIEnv *env, jobject obj) {
    return ptr_to_jstring(env, wimg_get_accounts());
}

// --- Recurring ---

JNIEXPORT jstring JNICALL JNI_FN(nativeGetRecurring)(JNIEnv *env, jobject obj) {
    return ptr_to_jstring(env, wimg_get_recurring());
}

JNIEXPORT jint JNICALL JNI_FN(nativeDetectRecurring)(JNIEnv *env, jobject obj) {
    return wimg_detect_recurring();
}

// --- Snapshots ---

JNIEXPORT jint JNICALL JNI_FN(nativeTakeSnapshot)(JNIEnv *env, jobject obj, jint year, jint month) {
    return wimg_take_snapshot(year, month);
}

JNIEXPORT jstring JNICALL JNI_FN(nativeGetSnapshots)(JNIEnv *env, jobject obj) {
    return ptr_to_jstring(env, wimg_get_snapshots());
}

// --- Undo/Redo ---

JNIEXPORT jstring JNICALL JNI_FN(nativeUndo)(JNIEnv *env, jobject obj) {
    return ptr_to_jstring(env, wimg_undo());
}

JNIEXPORT jstring JNICALL JNI_FN(nativeRedo)(JNIEnv *env, jobject obj) {
    return ptr_to_jstring(env, wimg_redo());
}

// --- Debts ---

JNIEXPORT jstring JNICALL JNI_FN(nativeGetDebts)(JNIEnv *env, jobject obj) {
    return ptr_to_jstring(env, wimg_get_debts());
}

JNIEXPORT jint JNICALL JNI_FN(nativeAddDebt)(JNIEnv *env, jobject obj, jstring json) {
    const char *data = (*env)->GetStringUTFChars(env, json, NULL);
    jsize len = (*env)->GetStringUTFLength(env, json);
    int32_t rc = wimg_add_debt((const uint8_t *)data, len);
    (*env)->ReleaseStringUTFChars(env, json, data);
    return rc;
}

JNIEXPORT jint JNICALL JNI_FN(nativeMarkDebtPaid)(JNIEnv *env, jobject obj, jstring id, jlong amountCents) {
    const char *cid = (*env)->GetStringUTFChars(env, id, NULL);
    jsize len = (*env)->GetStringUTFLength(env, id);
    int32_t rc = wimg_mark_debt_paid((const uint8_t *)cid, len, amountCents);
    (*env)->ReleaseStringUTFChars(env, id, cid);
    return rc;
}

JNIEXPORT jint JNICALL JNI_FN(nativeDeleteDebt)(JNIEnv *env, jobject obj, jstring id) {
    const char *cid = (*env)->GetStringUTFChars(env, id, NULL);
    jsize len = (*env)->GetStringUTFLength(env, id);
    int32_t rc = wimg_delete_debt((const uint8_t *)cid, len);
    (*env)->ReleaseStringUTFChars(env, id, cid);
    return rc;
}

// --- Goals ---

JNIEXPORT jstring JNICALL JNI_FN(nativeGetGoals)(JNIEnv *env, jobject obj) {
    return ptr_to_jstring(env, wimg_get_goals());
}

JNIEXPORT jint JNICALL JNI_FN(nativeAddGoal)(JNIEnv *env, jobject obj, jstring json) {
    const char *data = (*env)->GetStringUTFChars(env, json, NULL);
    jsize len = (*env)->GetStringUTFLength(env, json);
    int32_t rc = wimg_add_goal((const uint8_t *)data, len);
    (*env)->ReleaseStringUTFChars(env, json, data);
    return rc;
}

JNIEXPORT jint JNICALL JNI_FN(nativeContributeGoal)(JNIEnv *env, jobject obj, jstring id, jlong amountCents) {
    const char *cid = (*env)->GetStringUTFChars(env, id, NULL);
    jsize len = (*env)->GetStringUTFLength(env, id);
    int32_t rc = wimg_contribute_goal((const uint8_t *)cid, len, amountCents);
    (*env)->ReleaseStringUTFChars(env, id, cid);
    return rc;
}

JNIEXPORT jint JNICALL JNI_FN(nativeDeleteGoal)(JNIEnv *env, jobject obj, jstring id) {
    const char *cid = (*env)->GetStringUTFChars(env, id, NULL);
    jsize len = (*env)->GetStringUTFLength(env, id);
    int32_t rc = wimg_delete_goal((const uint8_t *)cid, len);
    (*env)->ReleaseStringUTFChars(env, id, cid);
    return rc;
}

// --- Export ---

JNIEXPORT jstring JNICALL JNI_FN(nativeExportCsv)(JNIEnv *env, jobject obj) {
    return ptr_to_jstring(env, wimg_export_csv());
}

JNIEXPORT jstring JNICALL JNI_FN(nativeExportDb)(JNIEnv *env, jobject obj) {
    return ptr_to_jstring(env, wimg_export_db());
}
