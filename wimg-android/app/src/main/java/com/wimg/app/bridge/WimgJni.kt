package com.wimg.app.bridge

/**
 * Raw JNI declarations mapping to wimg_jni.c native methods.
 * Each function corresponds to a C ABI function in libwimg.
 */
object WimgJni {
    init {
        System.loadLibrary("wimg")
        System.loadLibrary("wimg-jni")
    }

    // Lifecycle
    external fun nativeInit(dbPath: String): Int
    external fun nativeClose()
    external fun nativeGetError(): String?

    // Transactions
    external fun nativeGetTransactions(): String?
    external fun nativeGetTransactionsFiltered(account: String): String?
    external fun nativeSetCategory(id: String, category: Int): Int
    external fun nativeSetExcluded(id: String, excluded: Int): Int
    external fun nativeAutoCategorize(): Int

    // Summaries
    external fun nativeGetSummary(year: Int, month: Int): String?
    external fun nativeGetSummaryFiltered(year: Int, month: Int, account: String): String?

    // Import
    external fun nativeParseCsv(data: ByteArray): String?
    external fun nativeImportCsv(data: ByteArray): String?

    // Accounts
    external fun nativeGetAccounts(): String?

    // Recurring
    external fun nativeGetRecurring(): String?
    external fun nativeDetectRecurring(): Int

    // Snapshots
    external fun nativeTakeSnapshot(year: Int, month: Int): Int
    external fun nativeGetSnapshots(): String?

    // Undo/Redo
    external fun nativeUndo(): String?
    external fun nativeRedo(): String?

    // Debts
    external fun nativeGetDebts(): String?
    external fun nativeAddDebt(json: String): Int
    external fun nativeMarkDebtPaid(id: String, amountCents: Long): Int
    external fun nativeDeleteDebt(id: String): Int

    // Goals
    external fun nativeGetGoals(): String?
    external fun nativeAddGoal(json: String): Int
    external fun nativeContributeGoal(id: String, amountCents: Long): Int
    external fun nativeDeleteGoal(id: String): Int

    // Export
    external fun nativeExportCsv(): String?
    external fun nativeExportDb(): String?
}
