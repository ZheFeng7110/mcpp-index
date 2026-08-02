-- Form B inline descriptor for [Boost::ext].UT — the C++20 single-header
-- unit-testing framework shipped by the boost-ext org (NOT an official Boost
-- library; hence the `boost-ext` package namespace, NOT `compat` and NOT
-- `boost`). Exposed as the C++23 module `boost.ut` so users can write
-- `import boost.ut;` out of the box.
--
-- The upstream release tarball DOES ship an official module interface unit
-- at `include/boost/ut.cppm` (`export module boost.ut;`), but it cannot be
-- used VERBATIM on either of this index's two non-MSVC default toolchains:
--
--   * GCC 16.1 (--std=c++23) rejects the verbatim file with `-Wtemplate-body`:
--       ut.hpp:1916:5: error: 'size_t' was not declared in this scope;
--         did you mean 'std::size_t'?
--     In a modular TU `size_t` only enters scope via `#include <cstddef>` /
--     `using std::size_t;`, NOT via `export import std;` (which only brings
--     `std::size_t`). ut.hpp uses `size_t` unqualified at namespace scope.
--
--   * Clang 22.1 on the MSVC ABI (Windows default target) rejects the verbatim
--     file with `use of undeclared identifier '__argc'` (and `__argv`):
--     ut.hpp line 687 is `#if defined(_MSC_VER)` and references the MSVC
--     builtins `__argc` / `__argv`. Clang DOES set `_MSC_VER` on the MSVC
--     ABI but does NOT provide those builtins (the adjacent branches at
--     lines 291 / 311 / 1147 already gate clang out — line 687 was missed).
--     Tracked upstream as boost-ext/ut#656-style clang-on-windows gap.
--
-- So, like marzer.tomlplusplus, we provide a `generated_files` wrapper that
-- reproduces upstream's INTENT (ut.hpp included in the module purview with
-- `BOOST_UT_CXX_MODULES=1`, so the `export namespace boost::...{...}` block
-- ut.hpp opens at line 111 takes everything with it) and adds ONLY two
-- minimal shims: a `using std::size_t;` at purview top level (fixes GCC),
-- and `#define __argc 0` / `#define __argv nullptr` gated to `__clang__` on
-- `_MSC_VER` (fixes Clang-on-Windows; MSVC itself is untouched). The base
-- `ut.hpp` stays pinned to the reproducible v2.3.1 release tag — the shims
-- add NO code of our own beyond what the compiler had to see anyway.
--
-- include_dirs exposes `*/include/boost` so the wrapper's `#include "ut.hpp"`
-- resolves (and `#include <boost/ut.hpp>` remains available to consumers who
-- want the header form). The upstream path is a GLOB — the leading `*`
-- absorbs the archive's `ut-2.3.1/` wrap layer — while the generated cppm
-- path is verdir-relative (no glob), like nlohmann.json / marzer.tomlplusplus.
--
-- The native cppm also does `export import std;`, so consumers transitively
-- see stdlib symbols after `import boost.ut;`; `import_std` stays false to
-- avoid a duplicate `import std;` mcpp would otherwise inject into the
-- module's own TU.
--
-- License: Boost Software License 1.0. The SPDX identifier is BSL-1.0.
--
-- Package identity: `namespace = "boost-ext"`, `name = "ut"`; the C++20
-- namespace the library actually declares is `boost::ext::ut::v2_3_1` —
-- unrelated to the mcpp namespace, which uses `-` precisely because `.` would
-- collide with mcpp's own `<ns>.<short>` addressing convention.
package = {
    spec        = "1",
    namespace   = "boost-ext",
    name        = "ut",
    description = "[Boost::ext].UT — C++20 single-header unit testing framework, exposed as the C++23 module boost.ut",
    licenses    = {"BSL-1.0"},
    repo        = "https://github.com/boost-ext/ut",
    type        = "package",

    xpm = {
        linux = {
            ["2.3.1"] = {
                url    = "https://github.com/boost-ext/ut/archive/refs/tags/v2.3.1.tar.gz",
                sha256 = "e51bf1873705819730c3f9d2d397268d1c26128565478e2e65b7d0abb45ea9b1",
            },
        },
        macosx = {
            ["2.3.1"] = {
                url    = "https://github.com/boost-ext/ut/archive/refs/tags/v2.3.1.tar.gz",
                sha256 = "e51bf1873705819730c3f9d2d397268d1c26128565478e2e65b7d0abb45ea9b1",
            },
        },
        windows = {
            ["2.3.1"] = {
                url    = "https://github.com/boost-ext/ut/archive/refs/tags/v2.3.1.tar.gz",
                sha256 = "e51bf1873705819730c3f9d2d397268d1c26128565478e2e65b7d0abb45ea9b1",
            },
        },
    },

    mcpp = {
        schema       = "0.1",
        language     = "c++23",
        import_std   = false,
        modules      = { "boost.ut" },
        include_dirs = { "*/include/boost" },
        -- Upstream's ut.cppm reproduced VERBATIM apart from two minimal
        -- compiler-compat shims (documented at the top of this descriptor):
        --   1. `using std::size_t;` at the top of the purview (GCC fix).
        --   2. `#define __argc 0` / `#define __argv nullptr` gated to
        --      `__clang__` on the MSVC ABI (Clang-on-Windows fix; MSVC
        --      itself never enters the guard).
        -- Verdir-relative path, no glob — like nlohmann.json / marzer.tomlplusplus.
        generated_files = {
            ["mcpp_generated/boost.ut.cppm"] = [==[
module;

#if __has_include(<unistd.h>) and __has_include(<sys/wait.h>)
#include <sys/wait.h>
#include <unistd.h>
#endif

export module boost.ut;
export import std;

// ---- mcpp-index compat shim 1/2: GCC template-body fix -------------------
// Under the C++23 named-module purview, `size_t` is NOT introduced by
// `export import std;` (only `std::size_t` is). ut.hpp uses `size_t`
// unqualified at namespace scope (e.g. line 1916 of ut.hpp), which GCC 16.1
// rejects as `-Wtemplate-body` ("'size_t' was not declared in this scope").
// Pull `std::size_t` into the global purview so the unqualified name
// resolves inside the exported namespace block ut.hpp opens below.
using std::size_t;

// ---- mcpp-index compat shim 2/2: Clang-on-Windows fix ---------------------
// ut.hpp line 687 is `#if defined(_MSC_VER)` and references the MSVC
// builtins `__argc` / `__argv`. Clang on the MSVC ABI (x86_64-windows-msvc)
// sets `_MSC_VER` but does NOT provide those builtins — the neighboring
// upstream guards at lines 291 / 311 / 1147 already gate clang out, but
// line 687 missed it. Provide macros as stand-ins (cfg::largc is reassigned
// from main() args at runtime anyway, so the value is unused). MSVC itself
// never enters this guard, so its real builtins are untouched.
#if defined(_MSC_VER) and defined(__clang__)
  #define __argc 0
  #define __argv ((const char**)nullptr)
#endif

#define BOOST_UT_CXX_MODULES 1
#include "ut.hpp"

#if defined(_MSC_VER) and defined(__clang__)
  #undef __argc
  #undef __argv
#endif
]==],
        },
        sources      = { "mcpp_generated/boost.ut.cppm" },
        targets      = { ["boost_ut"] = { kind = "lib" } },
        deps         = { },
    },
}