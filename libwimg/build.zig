const std = @import("std");

pub fn build(b: *std.Build) void {
    // Default: wasm32-freestanding for the web target
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    const is_wasm = target.result.cpu.arch == .wasm32;

    // Stub libc include path for wasm32-freestanding
    const libc_include = b.path("vendor/libc");

    // --- WASM library (primary target) ---
    if (is_wasm) {
        const wasm_lib = b.addExecutable(.{
            .name = "libwimg",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/root.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });

        // Export all `export fn` symbols
        wasm_lib.entry = .disabled;
        wasm_lib.rdynamic = true;

        const wasm_sqlite_flags: []const []const u8 = &.{
            "-DSQLITE_OS_OTHER=1",
            "-DSQLITE_OMIT_WAL=1",
            "-DSQLITE_OMIT_LOAD_EXTENSION=1",
            "-DSQLITE_THREADSAFE=0",
            "-DSQLITE_TEMP_STORE=3",
            "-DSQLITE_OMIT_LOCALTIME=1",
            "-DSQLITE_DEFAULT_MEMSTATUS=0",
            "-DSQLITE_DEFAULT_SYNCHRONOUS=0",
            // NOT using SQLITE_OMIT_AUTOINIT — need sqlite3_open to call sqlite3_initialize/sqlite3_os_init
            "-DSQLITE_OMIT_DEPRECATED=1",
            "-DSQLITE_OMIT_PROGRESS_CALLBACK=1",
            "-DSQLITE_OMIT_SHARED_CACHE=1",
            "-DSQLITE_OMIT_UTF16=1",
            "-DSQLITE_OMIT_COMPLETE=1",
            "-DSQLITE_OMIT_DECLTYPE=1",
            "-DSQLITE_OMIT_GET_TABLE=1",
            "-DSQLITE_OMIT_TRACE=1",
            "-DSQLITE_OMIT_TCL_VARIABLE=1",
            "-DSQLITE_DQS=0",
            "-DSQLITE_CORE=1",
            "-DSQLITE_HAVE_ISNAN=1",
        };

        // Add stub libc headers for wasm32-freestanding C compilation
        wasm_lib.root_module.addIncludePath(libc_include);

        wasm_lib.root_module.addCSourceFile(.{
            .file = b.path("vendor/sqlite3.c"),
            .flags = wasm_sqlite_flags,
        });
        wasm_lib.root_module.addCSourceFile(.{
            .file = b.path("vendor/wasm_vfs.c"),
            .flags = &.{},
        });
        wasm_lib.root_module.addCSourceFile(.{
            .file = b.path("vendor/libc_shim.c"),
            .flags = &.{},
        });

        // Stack size for WASM
        wasm_lib.stack_size = 1 * 1024 * 1024; // 1 MB stack

        b.installArtifact(wasm_lib);

        // Copy wasm to wimg-web for dev
        const install_to_web = b.addInstallFile(
            wasm_lib.getEmittedBin(),
            "../wimg-web/static/libwimg.wasm",
        );
        install_to_web.step.dependOn(&wasm_lib.step);
        b.getInstallStep().dependOn(&install_to_web.step);
    } else {
        // --- Native library (for testing / iOS) ---
        const lib = b.addLibrary(.{
            .name = "wimg",
            .linkage = .static,
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/root.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });

        lib.root_module.addCSourceFile(.{
            .file = b.path("vendor/sqlite3.c"),
            .flags = &.{
                "-DSQLITE_OMIT_LOAD_EXTENSION=1",
                "-DSQLITE_THREADSAFE=0",
                "-DSQLITE_TEMP_STORE=2",
            },
        });
        lib.linkSystemLibrary("c");

        b.installArtifact(lib);
    }

    // --- Tests ---
    const test_step = b.step("test", "Run unit tests");

    const parser_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/parser.zig"),
            .target = b.resolveTargetQuery(.{}), // native for tests
            .optimize = optimize,
        }),
    });
    const run_parser_tests = b.addRunArtifact(parser_tests);
    test_step.dependOn(&run_parser_tests.step);

    const types_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/types.zig"),
            .target = b.resolveTargetQuery(.{}),
            .optimize = optimize,
        }),
    });
    const run_types_tests = b.addRunArtifact(types_tests);
    test_step.dependOn(&run_types_tests.step);
}
