# 收录 [Boost::ext].UT(boost-ext.ut)2.3.1

> 日期:2026-08-02
> 分支:`add-boost-ext-ut`(本地提交,未推送、未发 PR)
> 仓库:[boost-ext/ut](https://github.com/boost-ext/ut)
> 背景:用户要求将 boost-ext 组织(注意:不是 boost 官方)的 UT 单头测试框架收录进 mcpp-index,
> 自带 C++ 模块支持,模块单元位于 `include/boost/ut.cppm`,声明 `export module boost.ut;`。

## 1. 来源与形态判定

- 来源:**(a) 第三方上游库**。上游 boost-ext/ut 不提供 mcpp 支持,但其 release tarball **自带**官方模块单元
  `include/boost/ut.cppm`(`export module boost.ut;`),因此本仓不需自行从零合成 module wrapper,
  只需对上游 cppm 做最小兼容补丁(见 §2)。
- 版本:`v2.3.1`(截至 2026-08-02 的最新 release tag)。
- License:Boost Software License 1.0,SPDX 标识 `BSL-1.0`。
- 布局:tarball 顶层 wrap 目录为 `ut-2.3.1/`,模块单元位于 `include/boost/ut.cppm`,
  头文件 `include/boost/ut.hpp`(3378 行,定义 `namespace boost::inline ext::ut::inline v2_3_1`)。
- 形态:**C++23 module(generated wrapper)** —— 因上游 cppm 无法逐字编译(见 §2),采用
  `generated_files` 内嵌一份带两处最小 shim 的等价物,与 `marzer.tomlplusplus` 同类。

判据:逐字复用上游 cppm 的尝试在 mcpp 0.0.109 默认 toolchain 下均失败,详见 §2。

身份:`namespace = "boost-ext"`、`name = "ut"`。**NOT** `boost`、**NOT** `compat`:
用户明确指出该项目并非 boost 官方库,因此不能占用 `compat` 习惯位置,也不能放进 boost 命名空间,
更不能与 boost::ext 这一第三方组织混同于 mcpplibs 的既有命名空间。`boost-ext` 这一 mcpp 命名空间
用 `-` 分层,避免与 mcpp 既有 `<ns>.<short>` 点号寻址约定碰撞(与 `nlohmann.json` 走点号、
`marzer.tomlplusplus` 走点号属同一道理下的反向取舍)。

## 2. 关键注意事项:上游 ut.cppm 不能逐字内嵌

与 `nlohmann.json`(可 VERBATIM 内嵌)与 `marzer.tomlplusplus`(删一行后 VERBATIM 内嵌)不同,
上游 `ut-2.3.1/include/boost/ut.cppm` 在 mcpp 0.0.109 的两条非 MSVC 默认 toolchain 上**均无法编译**:

### 2.1 GCC 16.1(`-std=c++23`):-Wtemplate-body 拒绝无修饰 `size_t`

```
ut.hpp:1916:5: error: 'size_t' was not declared in this scope;
  did you mean 'std::size_t'? [-Wtemplate-body]
 1916 |     size_t n_tests = 0;
```

根因:ut.cppm 把 `#include "ut.hpp"` 放在 purview 内,只做了 `export import std;`。
在 named-module purview 中,`size_t` 并不通过 `export import std;` 进入作用域
(只有 `std::size_t` 进入)。ut.hpp 在多处用无修饰 `size_t`(行 1916/1917/1936/1937、
reporter_junit 模板体内),非模块编译时这条由前置 `<cstddef>` 等头链间接带入,模块下则显式缺失。

### 2.2 Clang 22.1(MSVC ABI / x86_64-windows-msvc):`__argc`/`__argv` 未声明

```
ut.hpp:688:29: error: use of undeclared identifier '__argc'; did you mean 'largc'?
  688 |   static inline int largc = __argc;
ut.hpp:689:63: error: use of undeclared identifier '__argv'; did you mean 'largv'?
```

根因:ut.hpp 行 687 `#if defined(_MSC_VER)` 引用 MSVC 内建 `__argc`/`__argv`。Clang 在 MSVC ABI
上设了 `_MSC_VER`,但不提供这两个内建 —— 上游相邻分支(行 291 / 311 / 1147)已通过
`&& !defined(__clang__)` 排除 clang,行 687 漏了同一守卫。属上游 clang-on-windows 模块适配缺口。

### 2.3 解法:generated_files 内嵌 + 两处最小 shim

`generated_files` 内嵌的 cppm 在逐字节复用上游 ut.cppm 的基础上**仅**插入两处 shim:

| shim | 作用 | 守卫 |
|---|---|---|
| `using std::size_t;`(purview 顶层) | 修复 GCC 的 `size_t` 未声明 | 无条件 |
| `#define __argc 0` / `#define __argv ((const char**)nullptr)` | 修复 Clang-on-Windows 的内建缺失 | `_MSC_VER && __clang__` |

要点:

- shim 1 的 `using std::size_t;` 在 purview 全局作用域,ut.hpp 在其内开
  `export namespace boost::inline ext::ut::inline v2_3_1 { ... }`,namespace block 内对 `size_t`
  的无修饰查找经 outer-namespace 回溯可见 `::size_t`(由 using 引入)。
- shim 2 仅在 `__clang__` 定义时启用,MSVC 本身不进入守卫,所以保留 MSVC 真内建行为不变。
  cfg::largc 在运行时由 ut.hpp 行 3373-3375 从 main argc/argv 重新赋值,宏值始终是占位 0,
  不影响行为。
- `BOOST_UT_CXX_MODULES=1` 这一定义照搬自上游 ut.cppm,从而
  `BOOST_UT_EXPORT` 被定义为 `export`,ut.hpp 行 111 的
  `BOOST_UT_EXPORT namespace boost::inline ext::ut::inline v2_3_1 { ... }` 即
  `export namespace boost::inline ext::ut::inline v2_3_1 { ... }`,
  该 namespace block 内所有声明都随 `export module boost.ut;` 一起 export 到消费者。
  这是上游 cppm 本来的设计;shims 不破坏该结构。

`include_dirs = { "*/include/boost" }` 让 wrapper 内的 `#include "ut.hpp"` 解析到 verdir 下的
实际 ut.hpp;同时消费者若直接 `#include <boost/ut.hpp>` 也能解析(与 nlohmann/marzer 同形式)。
generated cppm 路径 `mcpp_generated/boost.ut.cppm` 为 verdir 相对(无 glob),与既有同形态惯例一致。

## 3. 描述符

- 路径:`pkgs/b/boost-ext.ut.lua`(目录取**完整包名首字母** `b`)。
- 命名:`boost-ext.ut`,避免占用 `compat` 习惯位置与 `boost` 官方命名空间。
- 三平台 `xpm` 共用同一 url 与 sha256(GLOBAL-only;无 `mcpp-res` 写权限故走 plain-string url,
  lint 允许,CN 用户回退至上游源由维护者后续补充)。
- 版本号采用裸版本 `"2.3.1"`;URL 中保留上游 `…/v2.3.1.tar.gz` 拼写。

## 4. feature 评估

**不实现 feature**。ut 为纯头文件 + 模块单元,无"额外的可编译源码"可供门控。
其可选行为(`BOOST_UT_CONFIG_DISABLE_EXCEPTIONS` 等)均为编译期 **define**,
而 `features` 表当前仅能门控 `sources`,无法携带 define。
与 Eigen 的 `EIGEN_MPL2_ONLY`、toml++ 的 `TOML_EXCEPTIONS` 属同类限制,
待 mcpp 支持 define/cflags 后再评估。

## 5. CN 镜像

未配置。本地无 `mcpp-res` 写权限,lint 规则允许 plain-string 形式的 `url`
(见 `tests/check_mirror_urls.lua`:plain url 直接放行)。CN 镜像由维护者后续补充。

## 6. 验证结论

测试工程 `tests/examples/boost-ext.ut/`,已登记进根 `mcpp.toml` 的 `[workspace].members`
(本仓测试面为 `mcpp test -p <member>` / `mcpp test --workspace`)。断言覆盖 UDL 语法
(`"..."_test` = lambda { ... })、函数语法(`test("...") = lambda { ... }`)与
`expect()` 断言两路,直接由 [Boost::ext].UT 的 runner 输出判通过/失败:
`"Suite 'global': all tests passed (3 asserts in 2 tests)"`。

| 检查 | 结果 |
|---|---|
| `mcpp xpkg parse pkgs/b/boost-ext.ut.lua`(CI pin 0.0.109 与本地 2026.8.2.1) | ✅ parse OK |
| 全量 `mcpp xpkg parse pkgs/*/*.lua`(0.0.109) | ✅ 无 PARSE FAIL |
| `mcpp test -p boost-ext.ut`(gcc 16.1.0,Windows x86_64-windows-gnu 默认 target) | ✅ `all tests passed (3 asserts in 2 tests)` / `test result ok. 1 passed` |
| `mcpp test -p boost-ext.ut`(llvm 22.1.8,Windows x86_64-windows-msvc target) | ✅ `all tests passed (3 asserts in 2 tests)` / `test result ok. 1 passed` |
| `tests/check_mirror_urls.lua`(手算:plain-string url 直接放行) | ✅ 通过 |
| `tests/check_package_name.lua`(手算:`name = "ut"` 单一原子段) | ✅ 通过 |
| 前导 v 版本号 lint(手算:`"2.3.1"` 裸版本) | ✅ 通过 |

冷验证前已 `rm -rf tests/examples/boost-ext.ut/{target,.mcpp,mcpp.lock,compile_commands.json}`,
自干净状态走完"拉 tarball → 编译 wrapper → 编译/链接测试 → 运行"完整管线。

## 7. 其它

- 描述符注释里说明了与 `nlohmann.json`/`marzer.tomlplusplus` 的同与不同:
  上游 cppm 不能 VERBATIM 内嵌,但**无需**像 marzer 那样删去某一行,
  shim 只**追加**两处兼容补丁(verbatim 部分 + 两条 shim),不删除上游 cppm 任何字节,
  也不替换任何行;`generated_files` payload 不含 `]==]`。
- 提交策略:遵循用户指示,在新分支 `add-boost-ext-ut` 上 commit 一次,**不**推送、**不**发 PR/Issue。
  CI 自然不会运行;本设计文档与本地 `mcpp test` 输出作为等价证据保留。