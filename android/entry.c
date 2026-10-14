// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/android.md, section "entry.c"
// ============================================================================

// raylib's Android backend implements `android_main` and calls a C function
// named `main` from it. The Odin client is built as plain object files with no
// entry point of its own, so this shim provides `main` and forwards to the
// procedure the Odin side exports (client/src/android_entry.odin).

extern void tv_odin_main(void);

int main(int argc, char **argv)
{
    (void)argc;
    (void)argv;
    tv_odin_main();
    return 0;
}
