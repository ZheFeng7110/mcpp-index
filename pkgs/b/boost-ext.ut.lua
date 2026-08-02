-- Form B inline descriptor for [Boost::ext].UT — the C++20 single-header
-- unit-testing framework shipped by the boost-ext org (NOT an official Boost
-- library; hence the `boost-ext` package namespace, NOT `compat` and NOT
-- `boost`). Exposed as the C++23 module `boost.ut` so users can write
-- `import boost.ut;` out of the box.
--
-- The upstream release tarball DOES ship an official module interface unit
-- at `include/boost/ut.cppm` (`export module boost.ut;`), but it cannot be
-- used VERBATIM on this index's three CI platforms:
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
--   * Clang 20.1.7 (macOS CI's auto-installed default on macos-15) compiles
--     the verbatim file fine but the resulting test binary SIGSEGVs (exit
--     139) during static init of `cfg::runner<reporter_junit<printer>>` —
--     no "Suite '...'" output reaches stdout. A macOS lldb backtrace pins it
--     exactly:
--         frame #0: reporter_junit::reporter_junit at ut.hpp:1620:31
--         stop reason = EXC_BAD_ACCESS (code=1, address=0xffffffffffffffe8)
--     ut.hpp:1620 is the member-init `std::streambuf* cout_save =
--     std::cout.rdbuf();`. Root cause is a static-initialization ORDER
--     failure (SIOF): the module-exported inline variable
--     `cfg = runner<reporter_junit<printer>>{}` dynamically initializes
--     BEFORE Apple libc++'s `std::cout`, because libc++ does NOT attach an
--     init_priority / strong ios_base::Init ordering to its stream objects
--     the way MSVC STL and libstdc++ do — so `cfg`'s member-init reads an
--     unconstructed `std::cout` (hence the -0x18 garbage read). The
--     explicit-template-instantiation fix (below, dev 3) is upstream's
--     master-side change for a DIFFERENT Clang module codegen gap and does
--     NOT address this runtime init-order crash.
--
-- Upstream fixed a separate Clang module LINKAGE gap on `master` AFTER v2.3.1
-- by appending an explicit-template-instantiation block to ut.cppm — the
-- exact snippet the user pointed at:
--     template class boost::ut::reporter_junit<boost::ut::printer>;
--     template void boost::ut::reporter_junit<boost::ut::printer>::on<bool>(...);
--     template auto boost::ut::detail::test::operator=<>(...);
--     template auto boost::ut::expect<bool>(...);
--     template void boost::ut::reporter_junit<>::on<boost::ut::detail::fatal_<bool>>(...);
--     ... (three more on<...> overloads for `fatal_<bool>`)
-- We reproduce that block VERBATIM at the end of our generated cppm,
-- matching master byte-for-byte. No >2.3.1 release tag carries it yet, so
-- this is a minimal forward-port (same trust-path shape as marzer.tomlplusplus
-- carrying a one-line cut from master); once a >2.3.1 release ships it, we
-- can switch `sources` back to `*/include/boost/ut.cppm` and drop
-- `generated_files` entirely (the block comes back with it).
--
-- So, like marzer.tomlplusplus, we provide a `generated_files` wrapper that
-- reproduces upstream's INTENT (ut.hpp included in the module purview with
-- `BOOST_UT_CXX_MODULES=1`, so the `export namespace boost::...{...}` block
-- ut.hpp opens at line 111 takes everything with it) with THREE deliberate
-- deviations from VERBATIM:
--   dev 1. The v2.3.1 ut.cppm body is preserved VERBATIM through
--           `#include "ut.hpp";`.
--   dev 2. THREE minimal compiler-compat shims are ADDED at the top of the
--          purview before that include:
--          shim a: `using std::size_t;` — fixes the GCC `-Wtemplate-body`
--                  unqualified `size_t` error. std::size_t reaches the
--                  module TU through `export import std;`.
--          shim b: `#define __argc 0` / `#define __argv nullptr` gated to
--                   `__clang__` on `_MSC_VER` — fixes Clang-on-Windows
--                   (`__argc` / `__argv` builtins missing under
--                   `_MSC_VER`); MSVC itself never enters the guard.
--          shim c: a persistent `std::ios_base::Init` guard object — forces
--                   libc++'s std::cout/std::cin/std::cerr to construct
--                   BEFORE ut.hpp's `cfg` inline variable reads
--                   `std::cout.rdbuf()` in reporter_junit's ctor. This is
--                   THE fix for the macOS SIOF SIGSEGV (see the bullet
--                   above); without it macOS crashes at ut.hpp:1620.
--   dev 3. The post-v2.3.1 explicit-template-instantiation block (above) is
--          appended AFTER `#include "ut.hpp"`. It is upstream master's fix
--          for a separate Clang module LINKAGE gap and is kept verbatim
--          (it is a no-op on GCC/MSVC and harmless on Clang); it does NOT
--          by itself fix the macOS SIOF — shim c does that.
--
-- The base `ut.hpp` stays pinned to the reproducible v2.3.1 release tag —
-- the shims add NO code of our own beyond what the compiler/runtime had to
-- see anyway, and the appended instantiation block is upstream master's own
-- byte-for-byte fix.
--
-- include_dirs exposes `*/include/boost` so the wrapper's `#include "ut.hpp"`
-- resolves (and `#include <boost/ut.hpp>` remains available to consumers who
-- want the header form). The upstream path is a GLOB — the leading `*`
-- absorbs the archive's `ut-2.3.1/` wrap layer — while the generated cppm
-- path is verdir-relative (no glob), like nlohmann.json / marzer.tomlplusplus.
--
-- `export import std;` is preserved verbatim: removing it broke GCC's
-- template-body lookup for `std::empty`, `literals::operator""_test`, etc.
-- (cascade of `-Wtemplate-body` errors throughout gherkin.cpp & the
-- literals `using` block in ut.hpp:3311-3360). With it kept, consumers
-- transitively see stdlib symbols after `import boost.ut;`; `import_std`
-- stays false to avoid mcpp injecting a duplicate `import std;` into the
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
        -- Upstream's v2.3.1 ut.cppm reproduced with THREE deliberate deviations
        -- from VERBATIM (documented at the top of this descriptor):
        --   dev 1: v2.3.1 ut.cppm body preserved VERBATIM through
        --          `#include "ut.hpp";`.
        --   dev 2: two compiler-compat shims ADDED at the top of the purview
        --          (sized for GCC + clang-on-Windows MSVC ABI).
        --   dev 3: post-v2.3.1 explicit-template-instantiation block
        --          (lifted verbatim from upstream `master`) appended after
        --          `#include "ut.hpp"` to force-emission of the runner's
        --          dispatch targets; closes the macOS Clang 20.1.7 SIGSEGV.
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
// `export import std;` (a few lines above) brings `std::size_t` into the
// purview; this `using` lifts it into the global namespace so the
// unqualified `size_t` resolves inside the exported namespace block ut.hpp
// opens below.
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

// ---- mcpp-index compat shim 3/3: macOS std::cout static-init order (SIOF) --
// macOS CI (Apple Clang 20.1.7 + libc++) SIGSEGVs (exit 139) inside
// `reporter_junit::reporter_junit()` at ut.hpp:1620:
//     std::streambuf* cout_save = std::cout.rdbuf();
// EXC_BAD_ACCESS reading 0xffffffffffffffe8 (= -0x18). This is a static
// initialization ORDER failure: ut.hpp's module-exported inline variable
// `cfg = runner<reporter_junit<printer>>{}` dynamically initializes BEFORE
// libc++'s `std::cout` — libc++ has no init_priority on its stream objects,
// so across the module boundary the runner's member-init `std::cout.rdbuf()`
// reads an unconstructed `std::cout`. MSVC STL and libstdc++ guard their
// stream init with init_priority/ios_base::Init ordering, which is why the
// Windows + Linux legs pass; Apple libc++ does not.
// Fix: a persistent `std::ios_base::Init` guard object declared HERE, in the
// module purview BEFORE `#include "ut.hpp"`, so same-TU dynamic init runs it
// first (declaration order). Its constructor constructs std::cout/std::cin/
// std::cerr, so when `cfg` (declared later, inside ut.hpp) later reads
// `std::cout.rdbuf()` the object is fully built. It lives for the whole
// program, keeping the refcount >= 1 so streams are not torn down early.
// Anonymous namespace keeps it out of the module's exported interface.
namespace {
struct [[maybe_unused]] ut_iostream_guard {
    std::ios_base::Init init;
};
[[maybe_unused]] ut_iostream_guard ut_ensure_std_streams_ready{};
}

#define BOOST_UT_CXX_MODULES 1
#include "ut.hpp"

#if defined(_MSC_VER) and defined(__clang__)
  #undef __argc
  #undef __argv
#endif

// ---- mcpp-index deviation 3: post-v2.3.1 explicit template instantiations --
// Lifted VERBATIM from upstream `master`'s include/boost/ut.cppm. v2.3.1's
// ut.cppm stops at `#include "ut.hpp"`, which leaves the member templates
// the runner dispatches to (`reporter_junit<>::on<...>`, `test::operator=<>`,
// `expect<bool>`) only IMPLICITLY instantiable. Explicitly instantiating
// them forces emission — upstream's fix for a Clang module linkage gap.
// NOTE: this does NOT fix the macOS SIOF crash (ut.hpp:1620 `std::cout.rdbuf()`)
// — shim c above (the std::ios_base::Init guard) is the macOS fix. Keep
// both: dev 3 is verbatim upstream master, shim c is this index's addition.
// Once a >2.3.1 release ships this block, switch `sources` to
// `*/include/boost/ut.cppm` and drop `generated_files`; these lines come
// back with the verbatim upstream cppm (shim c stays until upstream also
// fixes the libc++ stream-init ordering for modules).
template class boost::ut::reporter_junit<boost::ut::printer>;
template void boost::ut::reporter_junit<boost::ut::printer>::on<bool>(boost::ut::events::log<bool>);
template void boost::ut::reporter_junit<boost::ut::printer>::on<bool>(boost::ut::events::assertion_pass<bool>);
template void boost::ut::reporter_junit<boost::ut::printer>::on<bool>(boost::ut::events::assertion_fail<bool>);
template auto boost::ut::detail::test::operator=<>(test_location<void (*)()> _test);
template auto boost::ut::expect<bool>(const bool&expr,const reflection::source_location&);
template void boost::ut::reporter_junit<>::on<boost::ut::detail::fatal_<bool>>(events::assertion_fail<boost::ut::detail::fatal_<bool>>);
template void boost::ut::reporter_junit<>::on<boost::ut::detail::fatal_<bool>>(events::assertion_pass<boost::ut::detail::fatal_<bool>>);
template void boost::ut::reporter_junit<>::on<boost::ut::detail::fatal_<bool>>(events::log<boost::ut::detail::fatal_<bool>>);
]==],
        },
        sources      = { "mcpp_generated/boost.ut.cppm" },
        targets      = { ["boost_ut"] = { kind = "lib" } },
        deps         = { },
    },
}