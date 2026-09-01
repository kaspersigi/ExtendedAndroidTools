# ExtendedAndroidTools Ubuntu 26.04 (Resolute) 本地构建说明

本文档介绍以下构建和验证脚本：

- `scripts/resolute-install-deps.sh`
- `scripts/resolute-local-build.sh`
- `scripts/verify-artifacts.sh`
- `scripts/generate-checksums.sh`
- `scripts/android-smoke-test.sh`

它们用于在 Ubuntu 26.04（代号 Resolute）x86_64 主机上直接构建
ExtendedAndroidTools，不依赖 Docker 构建环境。

`resolute-install-deps.sh` 负责安装主机依赖；
`resolute-local-build.sh` 负责选择或下载 Android NDK、校验构建环境、清理可选缓存，
以及调用项目 Makefile 完成本地交叉编译。默认的 `all` 构建还会验收六个产物、生成
`out/SHA256SUMS`，并在 adb 能唯一确定一台可用设备时自动执行真机 smoke test。


## 1. 适用环境

默认支持：

- 主机发行版：Ubuntu 26.04（Resolute）
- 主机架构：x86_64
- Android NDK：r27d
- Android API：35
- 普通单目标构建架构：arm64（`all` 固定构建 arm64 和 x86_64）
- 构建类型：Release
- 并行线程数：主机 `nproc` 返回的逻辑 CPU 数

构建脚本目前使用 NDK 的 `linux-x86_64` 预编译工具链，所以即使设置
`ALLOW_UNSUPPORTED_HOST=1`，主机架构仍然必须是 x86_64。

`ALLOW_UNSUPPORTED_HOST=1` 只跳过 Ubuntu 26.04 发行版检查，不表示其他发行版已经
测试或保证可用。


## 2. 最简构建流程

进入项目根目录：

```bash
cd /mnt/develop/linux/ExtendedAndroidTools
```

安装构建依赖：

```bash
./scripts/resolute-install-deps.sh
```

执行默认的 API 35、Release 全产物构建：

```bash
./scripts/resolute-local-build.sh
```

默认目标为 `all`。它依次构建 arm64 和 x86_64，每个架构生成完整包、精简包和静态
`bpftrace`，共六个发布产物：

```text
out/bpftools-arm64.tar.gz
out/bpftools-min-arm64.tar.gz
out/bpftrace-arm64
out/bpftools-x86_64.tar.gz
out/bpftools-min-x86_64.tar.gz
out/bpftrace-x86_64
```

中间文件和安装输出分别位于：

```text
build/
out/
projects/*/sources/
projects/*/.source-signature
```

以下生成内容均由仓库 `.gitignore` 忽略：

```text
build/
out/
projects/*/sources/
projects/*/.source-signature
```

因此，正常下载源码和执行构建不会把这些生成产物加入 Git 工作区状态。


## 3. resolute-install-deps.sh

### 3.1 功能

`resolute-install-deps.sh` 使用 Ubuntu 的 `apt-get` 安装本地构建所需的主机软件包。

脚本会执行：

```text
apt-get update
apt-get install -y --no-install-recommends ...
```

普通用户运行时使用 `sudo apt-get`；root 用户运行时直接使用 `apt-get`。

脚本安装的依赖包括：

```text
autoconf
automake
autopoint
binutils
bison
build-essential
bzip2
ca-certificates
curl
flex
file
g++
gettext
git
help2man
libssl-dev
libltdl-dev
libtool
make
patch
perl
pkg-config
po4a
python3
tar
texinfo
unzip
wget
xxd
zlib1g-dev
zstd
```

`perl` is required by the project-built OpenSSL configuration step. OpenSSL
ships a fallback copy of its required `Text::Template` Perl module, so a
separate CPAN installation is not required.

该脚本只安装主机软件包，不会：

- 下载或删除 Android NDK；
- 下载项目第三方源码；
- 启动项目构建；
- 使用 Docker；
- 修改项目源码版本。

### 3.2 基本用法

```bash
./scripts/resolute-install-deps.sh
```

查看帮助：

```bash
./scripts/resolute-install-deps.sh --help
```

在非 Ubuntu 26.04 系统上跳过发行版检查：

```bash
ALLOW_UNSUPPORTED_HOST=1 ./scripts/resolute-install-deps.sh
```

这只表示允许脚本继续执行。软件包名称、版本和兼容性仍由当前发行版负责，脚本不会
自动适配其他发行版。

如果以普通用户运行且系统没有 `sudo`，脚本会报错退出。此时需要安装 `sudo`，或由
root 用户执行脚本。


## 4. resolute-local-build.sh

### 4.1 功能

`resolute-local-build.sh` 是 Ubuntu 26.04 的本地构建入口，主要执行以下工作：

1. 根据环境变量解析构建参数；
2. 可选地执行模块源码清理或全量清理；
3. 检查 Ubuntu 版本和 x86_64 主机架构；
4. 检查本地构建命令是否齐全；
5. 选择已有 Android NDK，或在需要时下载 NDK；
6. 检查对应架构和 API 的 NDK Clang 驱动是否存在；
7. 将参数传给项目 Makefile，执行本地交叉编译；
8. 对 `all` 构建的六个产物执行压缩包、ELF、依赖和内容检查；
9. 生成 SHA-256 校验清单；
10. 根据 adb 设备状态决定执行或跳过真机测试。

脚本通过自身路径定位项目根目录，因此不要求当前 shell 必须位于项目根目录。

### 4.2 命令格式

```bash
./scripts/resolute-local-build.sh [target ...]
```

没有传入目标时，使用 `BUILD_TARGET`；`BUILD_TARGET` 的默认值为 `all`。`all` 是脚本提供
的特殊目标，会为 arm64 和 x86_64 构建全部六个发布产物：

```bash
./scripts/resolute-local-build.sh all
```

传入其他位置参数后，位置参数会覆盖 `BUILD_TARGET` 并原样作为 Make 目标传递：

```bash
./scripts/resolute-local-build.sh bpftools-min
```

也可以构建单独模块：

```bash
./scripts/resolute-local-build.sh llvm
./scripts/resolute-local-build.sh bcc
./scripts/resolute-local-build.sh bpftrace
./scripts/resolute-local-build.sh bpftrace-static
./scripts/resolute-local-build.sh python
```

位置参数最终会原样作为 Make 目标传递，因此也可以使用仓库 Makefile 提供的其他合法
目标。

查看脚本帮助：

```bash
./scripts/resolute-local-build.sh --help
```


## 5. 构建参数

所有参数都在 `resolute-local-build.sh` 顶部提供默认值，也可以在执行脚本时通过环境
变量覆盖。

### 5.1 BUILD_TARGET

默认值：

```text
all
```

指定没有位置参数时使用的 Make 目标：

```bash
BUILD_TARGET=bpftools-min ./scripts/resolute-local-build.sh
```

如果同时传入位置参数，则位置参数优先。

### 5.2 THREADS

默认值：

```bash
$(nproc)
```

该值传给项目内部的并行构建命令：

```bash
THREADS=16 ./scripts/resolute-local-build.sh
```

必须是大于零的整数。默认使用全部逻辑 CPU；如果主机内存不足或需要限制负载，可以
手动降低。

### 5.3 NDK_API

默认值：

```text
35
```

示例：

```bash
NDK_API=30 ./scripts/resolute-local-build.sh
```

脚本会检查 NDK 中是否存在对应 API 的 Clang 驱动，例如 arm64、API 35 对应：

```text
toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android35-clang
```

`NDK_API` 必须是大于零的整数。需要在较低 Android 版本上运行时，应根据目标设备选择
合适的最低 API，同时确保所选 NDK 提供对应工具链入口。

### 5.4 NDK_ARCH

默认值：

```text
arm64
```

支持以下值：

| NDK_ARCH | Android 编译三元组 | 典型设备架构 |
| --- | --- | --- |
| `arm64` | `aarch64-linux-android` | 64 位 ARM Android 设备 |
| `x86_64` | `x86_64-linux-android` | 64 位 x86 Android 设备/模拟器 |

本 fork 已移除 armv7/`armeabi-v7a` 构建路径；脚本和 Makefile 都会拒绝该值，不再生成、
验证或发布 32 位 ARM 产物。

示例：

```bash
NDK_ARCH=x86_64 ./scripts/resolute-local-build.sh bpftools
```

特殊目标 `all` 始终构建两个受支持架构，因此 `NDK_ARCH` 只影响普通 Make 目标。

不同架构的 Android 构建目录位于：

```text
build/android/<NDK_ARCH>/
out/android/<NDK_ARCH>/
```

### 5.5 NDK_VERSION

默认值：

```text
r27d
```

该值用于组成首选 NDK 路径、下载文件名和临时缓存目录：

```bash
NDK_VERSION=r27d ./scripts/resolute-local-build.sh
```

如果修改 NDK 版本，需要确保 Google 下载地址中存在相应的
`android-ndk-<version>-linux.zip`，或者同时提供 `NDK_DOWNLOAD_URL`。

### 5.6 NDK_PATH

默认值为空。

显式指定 NDK 目录时，它具有最高优先级：

```bash
NDK_PATH=/opt/android-ndk-r27d ./scripts/resolute-local-build.sh
```

如果显式目录不存在或缺少当前架构/API 的编译器，脚本直接报错，不会自动改用其他
NDK。

### 5.7 PREFERRED_NDK_PATH

默认值：

```text
/mnt/develop/android-ndk-r27d
```

实际默认值根据 `NDK_VERSION` 组成：

```text
/mnt/develop/android-ndk-${NDK_VERSION}
```

可以覆盖首选路径：

```bash
PREFERRED_NDK_PATH=/data/android/android-ndk-r27d \
    ./scripts/resolute-local-build.sh
```

### 5.8 NDK_TMP_DIR

默认值：

```text
/tmp
```

当没有显式 NDK，首选 NDK 也不存在时，脚本使用：

```text
${NDK_TMP_DIR}/android-ndk-${NDK_VERSION}
```

作为下载后的 NDK 缓存路径。

示例：

```bash
NDK_TMP_DIR=/var/tmp ./scripts/resolute-local-build.sh
```

下载首先发生在 `NDK_TMP_DIR` 下的随机 staging 目录中；下载和解压成功后才移动到最终
缓存路径。staging 目录在成功或失败后都会清理。

最终 NDK 缓存不会在构建完成后自动删除，以便后续复用。

### 5.9 NDK_DOWNLOAD_URL

默认值为空，此时使用 Google 官方形式的下载地址：

```text
https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-linux.zip
```

可以指定完整下载 URL：

```bash
NDK_DOWNLOAD_URL=https://example.invalid/android-ndk-r27d-linux.zip \
    ./scripts/resolute-local-build.sh
```

自定义压缩包解压后仍必须包含名为 `android-ndk-${NDK_VERSION}` 的顶层目录。

### 5.10 NDK_DOWNLOAD_SHA256

默认的 Google 官方 r27d Linux 压缩包摘要已经内置。使用其他 `NDK_VERSION` 或
`NDK_DOWNLOAD_URL` 触发下载时，必须显式提供对应的小写 SHA-256：

```bash
NDK_VERSION=r29 \
NDK_DOWNLOAD_SHA256=<64位十六进制摘要> \
    ./scripts/resolute-local-build.sh
```

摘要不匹配时，临时文件会被删除，NDK 不会解压或进入缓存目录。已有的显式 NDK 目录
不会重新压缩计算摘要；该参数保护的是脚本自动下载的归档。

### 5.11 DOWNLOAD_NDK

默认值：

```text
1
```

设置为 `0` 可以禁止自动下载：

```bash
DOWNLOAD_NDK=0 ./scripts/resolute-local-build.sh
```

此时如果没有找到已有 NDK，脚本会报错退出。

### 5.12 BUILD_TYPE

默认值：

```text
Release
```

支持：

```text
Release
Debug
```

Debug 示例：

```bash
BUILD_TYPE=Debug ./scripts/resolute-local-build.sh
```

其他大小写或其他值都会被拒绝。

### 5.13 STATIC_LINKING

默认值：

```text
false
```

必须是 `true` 或 `false`：

```bash
STATIC_LINKING=true ./scripts/resolute-local-build.sh
```

该值传给项目 Makefile，用于支持静态链接的组件。是否能够完全静态化仍取决于具体
项目、NDK 和依赖库的构建规则。

### 5.14 LLVM_BPF_ONLY

默认值：

```text
false
```

设置为 `true` 时，只为 LLVM 启用 BPF target：

```bash
LLVM_BPF_ONLY=true ./scripts/resolute-local-build.sh
```

这样可以缩小 LLVM 构建内容，但并非所有工具都能工作。例如 BCC 的 rwengine 还需要
当前 Android 架构对应的 LLVM target。需要完整功能时应保留默认值 `false`。

### 5.15 ALLOW_UNSUPPORTED_HOST

默认值：

```text
0
```

跳过 Ubuntu 26.04 发行版检查：

```bash
ALLOW_UNSUPPORTED_HOST=1 ./scripts/resolute-local-build.sh
```

该变量不会跳过 x86_64 检查，也不会自动修复其他系统上的依赖、编译器或 ABI 差异。

### 5.16 VERIFY_ARTIFACTS

默认值为 `1`。`all` 构建完成后会调用 `verify-artifacts.sh` 验证六个产物。设置为 `0`
可以临时跳过离线验收，但不建议用于发布构建：

```bash
VERIFY_ARTIFACTS=0 ./scripts/resolute-local-build.sh all
```

### 5.17 DEVICE_TEST

支持 `auto`、`required` 和 `0`，默认是 `auto`：

- `auto`：只有 adb 能确定唯一一台处于 `device` 状态的受支持设备时才测试，否则跳过；
- `required`：没有满足条件的设备也视为失败；
- `0`：明确禁用真机测试。

多设备环境应通过 `ANDROID_SERIAL` 选择目标。在线 pip 和 root BPF 探针的严格程度还可
分别通过 `DEVICE_NETWORK_REQUIRED=1`、`DEVICE_BPF_REQUIRED=1` 提高。


## 6. Android NDK 选择顺序

脚本按以下顺序选择 NDK：

1. 如果 `NDK_PATH` 非空，直接使用 `NDK_PATH`；
2. 否则，如果 `PREFERRED_NDK_PATH` 已存在，使用该目录；
3. 否则，检查 `${NDK_TMP_DIR}/android-ndk-${NDK_VERSION}`；
4. 如果临时缓存也不存在并且 `DOWNLOAD_NDK=1`，现场下载和解压；
5. 最后验证当前架构和 API 对应的 Clang 驱动是否可执行。

默认情况下，这一顺序等价于：

```text
显式 NDK_PATH
  -> /mnt/develop/android-ndk-r27d
  -> /tmp/android-ndk-r27d
  -> 下载到 /tmp/android-ndk-r27d
```

如果已选择的显式目录或首选目录存在但内容不完整，脚本不会覆盖它，也不会静默回退到
另一个 NDK，而是报错退出。

如果 `/tmp/android-ndk-r27d` 已存在但不完整，脚本同样不会覆盖。应先检查目录内容，
确认不再需要后再由用户手动处理。


## 7. 构建目标与产物

所有发布产物统一写入仓库的 `out/` 目录，不再把压缩包写到仓库根目录。

### 7.1 all

默认的全产物构建：

```bash
./scripts/resolute-local-build.sh all
```

该特殊目标对 arm64 和 x86_64 分别执行一次共享构建。同一架构的完整包、精简包和静态
`bpftrace` 复用 LLVM、BCC 及其他依赖，只为静态 `bpftrace` 保留独立的 CMake 构建目录，
避免静态与动态链接配置相互覆盖。宿主机上的 `llvm-config`、`llvm-tblgen` 和
`clang-tblgen` 一次构建时同时启用 AArch64、BPF 和 X86 后端，由两个 Android 架构共享；
Android LLVM 目标库仍按架构各构建一次。最终生成：

```text
out/bpftools-arm64.tar.gz
out/bpftools-min-arm64.tar.gz
out/bpftrace-arm64
out/bpftools-x86_64.tar.gz
out/bpftools-min-x86_64.tar.gz
out/bpftrace-x86_64
```

`all` 不能和其他位置参数组合。它固定使用完整的架构加 BPF LLVM targets，并按产物分别
处理动态和静态链接；`NDK_ARCH`、`STATIC_LINKING` 和 `LLVM_BPF_ONLY` 不用于改变这六项
产物集合。

### 7.2 bpftools

默认完整包：

```bash
./scripts/resolute-local-build.sh bpftools
```

主要包含：

- `bpftrace`；
- 可用时包含 `bpftrace-aotrt`；
- `projects/versions.mk` 当前选择的 Python 可执行程序和运行库；
- 与该 CPython 版本配套的 `pip`/`pip3` 入口；
- Python HTTPS 所需的 OpenSSL 动态库和 CA 证书包；
- Python `compression.zstd` 所需的 Zstandard 动态库；
- BCC 与 BPF 相关动态库；
- `libclang.so`；
- `libbpf`、`libelf`、`liblzma`、`libffi` 等运行库；
- bcc 与 bpftrace 的共享数据；
- 启动包装脚本和许可证文件。

产物名称由 `NDK_ARCH` 决定：

```text
out/bpftools-arm64.tar.gz
out/bpftools-x86_64.tar.gz
```

### 7.3 bpftools-min

精简包：

```bash
./scripts/resolute-local-build.sh bpftools-min
```

精简包保留 bpftrace 运行所需的核心二进制和库，不包含完整包中的 Python 环境、
`libbcc.so` 和 bcc 共享数据。

产物名称为：

```text
out/bpftools-min-arm64.tar.gz
out/bpftools-min-x86_64.tar.gz
```

### 7.4 bpftrace-static

只为 `NDK_ARCH` 选择的架构生成一个独立静态二进制：

```bash
NDK_ARCH=arm64 ./scripts/resolute-local-build.sh bpftrace-static
NDK_ARCH=x86_64 ./scripts/resolute-local-build.sh bpftrace-static
```

产物分别为 `out/bpftrace-arm64` 和 `out/bpftrace-x86_64`。该目标使用独立 CMake 目录，
但会复用相同架构已经安装的 LLVM 和其他依赖；普通 `bpftrace` 目标的动态安装结果不会被
替换。

### 7.5 单独构建模块

可以传入项目 Makefile 中的模块目标，例如：

```bash
./scripts/resolute-local-build.sh llvm
./scripts/resolute-local-build.sh bcc
./scripts/resolute-local-build.sh bpftrace
./scripts/resolute-local-build.sh python
./scripts/resolute-local-build.sh xz
```

单独构建模块主要用于开发和定位编译问题，不一定生成最终的 `out/bpftools-*.tar.gz`。

### 7.6 统一版本管理与逐模块升级

所有可下载组件和主机 Python 包的版本都集中在：

```text
projects/versions.mk
```

`psf/black` GitHub Action 是唯一例外。由于 workflow 不能直接读取 Make 变量，而且第三方
Action 的提交 SHA、Action release 和传入的 Black 版本必须作为一组审核，
`.github/workflows/black.yml` 会独立固定该版本。升级 Black 时需要同时更新
`projects/versions.mk` 中的 `BLACK_VERSION`、workflow 的 Action SHA、版本注释和 `version`
输入；其余项目版本仍只在 `projects/versions.mk` 维护。

Python 只需要在清单中设置一次完整版本：

```make
PYTHON_VERSION := <major.minor.patch>
```

`PYTHON_ABI_VERSION`、`PYTHON_BINARY`、源码 tag、主机解释器路径、Android
`site-packages` 路径和按架构隔离的 `python.xinstall` 都由该值推导。不要再在模块、sysroot
或 workflow 中加入 `python3.<minor>` 路径。普通的 `python3` 仍可作为主机依赖命令或最终包
内的兼容入口，它不代表固定某个 Python 次版本。

建议一次只升级一个模块，便于把失败归因到明确的上游变化：

```bash
# 1. 修改 projects/versions.mk 中一个模块的版本
# 2. 先验证模块本身；源码签名会自动刷新不匹配的源码目录
./scripts/resolute-local-build.sh python

# 3. 再验证最终依赖链和两个包
./scripts/resolute-local-build.sh bpftools bpftools-min
```

将 `python` 替换为 `ffi`、`xz`、`zstd`、`elfutils`、`bcc` 或其他项目名即可。模块使用 Git
提交而不是 release tag 时，也只在 `projects/versions.mk` 更新提交哈希。LLVM 同样在该文件
声明，但当前项目明确固定为 `llvmorg-21.1.8`。OpenSSL 的 LTS 版本和 CPython 内置的
pip wheel 版本也分别由 `OPENSSL_VERSION`、`PIP_VERSION` 统一声明；升级 Python 时应同步
确认源码树 `Lib/ensurepip/_bundled/` 中的 pip wheel 文件名并更新 `PIP_VERSION`。

每个下载或生成的源码目录都有一个被 Git 忽略的
`projects/<module>/.source-signature`。版本、仓库、归档摘要或补丁输入发生变化时，旧
`sources/` 会自动删除并按新声明重新获取。Python、OpenSSL、Zstandard、BCC、bpftrace 和 LLVM
另外记录构建配置签名；NDK、API、架构、链接模式或关键构建规则变化时会在原构建目录
重新配置。NDK 的 `libc++_shared.so` 也有独立签名；切换 NDK 路径、版本或库文件内容时会
自动刷新输出副本。LLVM、libbpf、elfutils、Zstandard 和 OpenSSL 在重新安装前还会清除各自旧的
版本化共享库族，避免共享输出目录中的旧 SONAME 文件被打进新发布包。`CLEAN_MODULES`
仍可用于人工排障，但不再是日常修改版本号后的必需步骤。

不同 `NDK_ARCH` 的 `python.xinstall` 分别生成在：

```text
build/android/<NDK_ARCH>/python.xinstall
```

因此依次构建 arm64 和 x86_64 时，不会让后一个架构的 BCC Python 安装误用前一个架构的
`site-packages` 路径。

### 7.7 Android 上使用 HTTPS 和 pip

HTTPS 和 pip 只包含在完整 `bpftools` 包中。构建并部署：

```bash
./scripts/resolute-local-build.sh bpftools
adb push out/bpftools-arm64.tar.gz /data/local/tmp/
adb shell 'cd /data/local/tmp && tar -xzf bpftools-arm64.tar.gz'
```

检查 Python、OpenSSL 和 pip：

```bash
adb shell /data/local/tmp/bpftools/python3 \
    -c 'import ssl; print(ssl.OPENSSL_VERSION)'
adb shell /data/local/tmp/bpftools/pip3 --version
```

直接安装到完整包自己的 `site-packages`：

```bash
adb shell /data/local/tmp/bpftools/pip3 install requests rich
```

也可以安装到独立目录，避免修改已经解压的工具包：

```bash
adb shell 'mkdir -p /data/local/tmp/python-packages && \
    /data/local/tmp/bpftools/pip3 install \
        --target /data/local/tmp/python-packages requests rich'

adb shell 'PYTHONPATH=/data/local/tmp/python-packages \
    /data/local/tmp/bpftools/python3 -c "import requests, rich"'
```

运行包装脚本时会自动设置包内动态库路径、OpenSSL provider 路径和 CA 证书文件。
调用者已经设置 `SSL_CERT_FILE` 或 `OPENSSL_MODULES` 时，脚本保留调用者的配置。

pip 可以安装纯 Python wheel，以及 PyPI 上与当前 Python ABI、Android API 和 CPU 架构
兼容的 Android wheel。只有原生源码包、只有普通 Linux wheel 的包，仍可能因为缺少
Android wheel、编译器、头文件或目标库而无法在设备上现场构建。Android root shell 中
运行 pip 时出现 root 用户警告属于 pip 的通用提示；希望隔离安装内容时优先使用
`--target`。

### 7.8 源码与构建配置签名

每个 Android 架构的 NDK libc++、LLVM、Python、OpenSSL、Zstandard、elfutils、libbpf、
stdc++fs、BCC 和 bpftrace 都有自动生成的配置签名，例如：

```text
build/android/<NDK_ARCH>/llvm.config
build/android/<NDK_ARCH>/libcxx-shared.config
build/android/<NDK_ARCH>/python.config
build/android/<NDK_ARCH>/openssl.config
build/android/<NDK_ARCH>/zstd.config
build/android/<NDK_ARCH>/elfutils.config
build/android/<NDK_ARCH>/libbpf.config
build/android/<NDK_ARCH>/stdc++fs.config
build/android/<NDK_ARCH>/bcc.config
build/android/<NDK_ARCH>/bpftrace.config
```

签名记录源码版本和实际提交、NDK 路径和版本、API、架构、CMake/Python 版本、构建类型、
`STATIC_LINKING`、`LLVM_BPF_ONLY`、LLVM targets、动态库选项及各模块的关键配置输入。
其中 `libcxx-shared.config` 还记录 NDK 库文件的 SHA-256，因此即使原文件时间戳没有变，
内容变化也会触发重新复制。
该文件位于已被 `.gitignore` 排除的 `build/` 目录，不会修改 Git 工作树。

每次构建都会重新计算签名，但内容相同时不会更新时间戳，也不会重新配置或编译 LLVM。
配置发生变化时，构建会打印新旧字段差异，自动在原目录重新运行对应配置步骤；源码和
依赖模块的完成标记也会直接传播到最终构建目标，触发下游模块按需重新配置和链接。例如从
`STATIC_LINKING=true` 切回动态完整包时，不再需要为了恢复 `libLLVM.so` 手动清理 LLVM
缓存。

切换 `LLVM_BRANCH_OR_TAG` 时，LLVM 源码签名会自动重新获取对应源码；同一份源码切换
动态/静态 LLVM 配置时，构建配置签名会在原目录重新运行 CMake。通常不再需要手动清理
LLVM，只有排查上游构建系统没有正确处理的残留状态时才使用 `CLEAN_MODULES=llvm`。


## 8. 清理功能

默认不执行清理，因此普通运行属于增量构建：

```bash
./scripts/resolute-local-build.sh
```

清理参数包括：

- `CLEAN_MODULES`
- `CLEAN_ALL`
- `CLEAN_ONLY`

三种最常用的执行方式如下：

```bash
# 清理 LLVM 源码和共享构建产物，然后立即开始构建
CLEAN_MODULES=llvm ./scripts/resolute-local-build.sh

# 只清理 LLVM 源码和共享构建产物，清理完成后退出
CLEAN_MODULES=llvm CLEAN_ONLY=1 ./scripts/resolute-local-build.sh

# 如果上一步已经只执行了清理，使用普通构建命令开始构建
./scripts/resolute-local-build.sh
```

只要设置 `CLEAN_ONLY=1`，脚本完成清理后就一定退出，不会继续检查 NDK 或启动构建。
如果希望“清理后立即构建”，不要设置 `CLEAN_ONLY=1`。

### 8.1 CLEAN_MODULES

指定一个或多个需要删除源码缓存并重新获取的模块。

单模块：

```bash
CLEAN_MODULES=llvm ./scripts/resolute-local-build.sh
```

逗号分隔多个模块：

```bash
CLEAN_MODULES=llvm,bcc ./scripts/resolute-local-build.sh
```

空格分隔时需要引号：

```bash
CLEAN_MODULES="llvm bcc" ./scripts/resolute-local-build.sh
```

模块名称会先通过 Makefile 的 `remove-<module>-sources` 目标校验。无效模块会在任何清理
发生之前报错退出。

需要特别注意：多个项目会把安装文件写入共享的 `out/` 目录，Makefile 没有完整的
逐模块安装清单。因此为了避免残留旧库或 ABI 不一致，设置 `CLEAN_MODULES` 时会：

1. 删除整个 `build/`；
2. 删除整个 `out/`；
3. 删除旧版本可能留在根目录下的 `bpftools-*.tar.gz`；
4. 只删除 `CLEAN_MODULES` 指定模块的源码缓存；
5. 默认继续执行构建。

也就是说，构建产物会全量重建，但没有被指定的其他模块源码仍然保留，不需要重新
下载。

LLVM 版本切换示例：

```bash
CLEAN_MODULES=llvm ./scripts/resolute-local-build.sh
```

这会删除旧的 `projects/llvm/sources` 和全部构建输出，然后根据
`projects/versions.mk` 当前设置的 tag 重新下载 LLVM 并开始构建。

### 8.2 CLEAN_ALL

完整清理全部构建产物和全部已下载项目源码，然后重新构建：

```bash
CLEAN_ALL=1 ./scripts/resolute-local-build.sh
```

该操作会删除：

```text
build/
out/
projects/*/sources/
```

它不会删除仓库外的 NDK，包括：

```text
/mnt/develop/android-ndk-r27d
/tmp/android-ndk-r27d
```

`CLEAN_ALL=1` 和非空的 `CLEAN_MODULES` 不能同时使用。

### 8.3 CLEAN_ONLY

默认值为 `0`。设置为 `1` 时，只执行已经请求的清理，不启动后续构建。

需要特别注意：`CLEAN_ONLY` 的含义是“仅清理”，不是“使用干净环境构建”。

只清理 LLVM 相关源码缓存和共享构建产物：

```bash
CLEAN_MODULES=llvm CLEAN_ONLY=1 ./scripts/resolute-local-build.sh
```

只执行全量清理：

```bash
CLEAN_ALL=1 CLEAN_ONLY=1 ./scripts/resolute-local-build.sh
```

`CLEAN_ONLY=1` 必须与 `CLEAN_MODULES` 或 `CLEAN_ALL=1` 一起使用，否则脚本会报错。

如果已经执行：

```bash
CLEAN_MODULES=llvm CLEAN_ONLY=1 ./scripts/resolute-local-build.sh
```

并看到以下信息：

```text
Cleanup completed; CLEAN_ONLY=1, so no build was started.
```

说明清理已经成功，只是构建按要求没有启动。随后直接运行：

```bash
./scripts/resolute-local-build.sh
```

即可在现有清理结果上开始构建，不需要再次设置 `CLEAN_MODULES=llvm`。


## 9. 常用构建示例

### 9.1 默认构建全部六个产物

```bash
./scripts/resolute-local-build.sh
```

这等价于显式传入 `all`，会构建 arm64 和 x86_64 的全部六个产物。

### 9.2 arm64 精简包

```bash
./scripts/resolute-local-build.sh bpftools-min
```

### 9.3 x86_64、API 35、16 线程

```bash
NDK_ARCH=x86_64 NDK_API=35 THREADS=16 \
    ./scripts/resolute-local-build.sh bpftools bpftools-min bpftrace-static
```

### 9.4 Debug 构建

```bash
BUILD_TYPE=Debug ./scripts/resolute-local-build.sh
```

### 9.5 使用指定 NDK

```bash
NDK_PATH=/mnt/develop/android-ndk-r27d \
    ./scripts/resolute-local-build.sh
```

### 9.6 禁止自动下载 NDK

```bash
DOWNLOAD_NDK=0 ./scripts/resolute-local-build.sh
```

### 9.7 切换 LLVM tag 后自动刷新源码并构建

更新 `projects/versions.mk` 中的 `LLVM_BRANCH_OR_TAG` 后直接运行：

```bash
./scripts/resolute-local-build.sh llvm
```

源码签名会使旧 LLVM 源码目录失效；无需预先执行模块清理。

### 9.8 全量重新构建但保留所有第三方源码

项目原有 Makefile 提供 `clean` 目标，只删除 `build/` 和 `out/`：

```bash
./scripts/resolute-local-build.sh clean
./scripts/resolute-local-build.sh
```

该方式不会删除源码缓存；与 `CLEAN_MODULES` 不同，它也不会主动删除已有
`out/bpftools-*.tar.gz`。需要严格清理打包产物时，使用 `CLEAN_MODULES` 或 `CLEAN_ALL`。


## 10. 参数组合规则

以下组合有效：

```bash
CLEAN_MODULES=llvm ./scripts/resolute-local-build.sh
CLEAN_MODULES=llvm,bcc CLEAN_ONLY=1 ./scripts/resolute-local-build.sh
CLEAN_ALL=1 ./scripts/resolute-local-build.sh
CLEAN_ALL=1 CLEAN_ONLY=1 ./scripts/resolute-local-build.sh
```

以下组合无效：

```bash
CLEAN_ALL=1 CLEAN_MODULES=llvm ./scripts/resolute-local-build.sh
CLEAN_ONLY=1 ./scripts/resolute-local-build.sh
THREADS=0 ./scripts/resolute-local-build.sh
NDK_API=abc ./scripts/resolute-local-build.sh
STATIC_LINKING=1 ./scripts/resolute-local-build.sh
```

其中 `STATIC_LINKING` 和 `LLVM_BPF_ONLY` 使用 `true/false`；`CLEAN_ALL`、
`CLEAN_ONLY`、`DOWNLOAD_NDK` 和 `ALLOW_UNSUPPORTED_HOST` 使用 `0/1`。


## 11. 常见错误与处理

### 11.1 主机版本不匹配

错误类似：

```text
error: this script supports Ubuntu 26.04 (Resolute)
```

首先确认 `/etc/os-release`。如果明确要在未验证系统上尝试，可以设置：

```bash
ALLOW_UNSUPPORTED_HOST=1 ./scripts/resolute-local-build.sh
```

### 11.2 缺少构建命令

错误类似：

```text
error: missing build commands: ...
```

运行：

```bash
./scripts/resolute-install-deps.sh
```

然后重新构建。

### 11.3 NDK 中缺少对应编译器

错误类似：

```text
error: selected NDK does not contain the expected compiler: ...
```

检查：

- `NDK_PATH` 是否指向 NDK 根目录；
- `NDK_VERSION` 是否与目录一致；
- `NDK_ARCH` 是否正确；
- `NDK_API` 是否为 NDK 支持的 API；
- NDK 是否完整解压。

### 11.4 临时 NDK 目录存在但不完整

错误类似：

```text
error: temporary NDK path exists but is incomplete
```

脚本不会自动覆盖已有目录。先检查该目录，确认其中没有需要保留的内容，再手动修复或
移走，然后重新运行脚本。

### 11.5 源码签名触发自动刷新

修改 `projects/versions.mk` 中的 tag、版本号、提交哈希或归档摘要后，对应的
`projects/<module>/.source-signature` 会发生变化，下一次构建将删除旧 `sources/` 并获取
新版本。日志会打印签名差异，便于确认究竟是哪一项触发了刷新。

如果下载被中断，重新运行同一构建命令即可；归档先写入临时文件，只有摘要验证通过后
才会原子替换正式缓存。需要排查异常残留时仍可使用 `CLEAN_MODULES=<module>` 强制清理。

### 11.6 增量构建状态异常

如果构建参数、工具链或源码发生较大变化，旧 CMake/Autotools 缓存可能不再适用。

保留源码、重建全部输出：

```bash
./scripts/resolute-local-build.sh clean
./scripts/resolute-local-build.sh
```

重新获取指定源码并重建：

```bash
CLEAN_MODULES=llvm ./scripts/resolute-local-build.sh
```

全部重新获取并重建：

```bash
CLEAN_ALL=1 ./scripts/resolute-local-build.sh
```

### 11.7 Flex 的 `malloc` 在 GCC 15 上编译失败

Ubuntu 26.04 的 GCC 15 默认使用 GNU C23。旧 Flex 源码中的无参数原型
`void *malloc()` 在 C23 中表示函数不接受参数，因此调用 `malloc(n)` 时会出现：

```text
error: too many arguments to function 'malloc'; expected 0, have 1
```

仓库已将 Flex 固定到 2026 年 7 月 30 日的上游 master 提交
`4fcc71489ae298c35b0b786114ad524945f2cf95`，其中已经包含 C23 `malloc` 原型修复。如果
错误发生前已经下载了旧 Flex 源码，当前源码签名机制会识别提交哈希变化并自动刷新
`projects/flex/sources`。正常情况下直接重新构建即可：

```bash
./scripts/resolute-local-build.sh
```

这个新 Flex 提交还会在非交叉编译的主机构建中执行二阶段 bootstrap 一致性检查。该检查
在高并发 `make install` 时可能让两个规则同时生成 `stage1scan.o`，表现为：

```text
mv: cannot stat '.deps/stage1scan.Tpo': No such file or directory
Bootstrap comparison failure!
```

项目生成的 host Flex 只是后续交叉构建工具，并不需要验证 Flex 上游源码能否自举。因此
host Flex 配置固定使用上游支持的 `--disable-bootstrap`，消除这项并行竞态；Android Flex
交叉构建仍保留原有配置。


## 12. 构建前后的建议检查

查看脚本实际默认值和帮助：

```bash
./scripts/resolute-local-build.sh --help
```

确认 NDK：

```bash
test -x /mnt/develop/android-ndk-r27d/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android35-clang
```

构建后检查产物：

```bash
ls -lh out/bpftools-*.tar.gz out/bpftrace-arm64 out/bpftrace-x86_64
./scripts/verify-artifacts.sh
(cd out && sha256sum --check SHA256SUMS)
```

也可以独立调用 `android-smoke-test.sh`。没有唯一可用设备时默认成功跳过，不会因为没有
连接手机而让本地构建失败：

```bash
./scripts/android-smoke-test.sh
DEVICE_TEST=required DEVICE_NETWORK_REQUIRED=1 \
    ./scripts/android-smoke-test.sh
```

确认生成文件没有意外进入 Git 状态：

```bash
git status --short
```

需要注意：脚本自身、本文档以及项目构建配置的有意修改仍会正常显示在 Git 状态中；
`.gitignore` 只负责忽略下载源码、构建目录、输出目录和打包产物。


## 13. GitHub Actions 构建环境

Android 工具包自动构建由 `.github/workflows/bpftools.yml` 负责。该 workflow 与本文档
描述的本地构建环境保持一致：

- GitHub runner：`ubuntu-26.04`；
- Android API：35；
- Android NDK：r27d；
- 构建入口：`scripts/resolute-local-build.sh`；
- 依赖安装入口：`scripts/resolute-install-deps.sh`；
- 架构矩阵：arm64 和 x86_64；
- 并行线程数：不在 workflow 中写死，由脚本使用 `nproc` 自动匹配 runner CPU 数量。

workflow 保留六个独立上传产物：arm64/x86_64 各自的完整包、精简包和静态
`bpftrace`，没有通过减少目标或架构来换取构建速度。

当前配置面向 GitHub 免费标准 runner，不使用需要额外付费的 larger runner。公开仓库的
标准 Linux runner 当前提供 4 个 CPU，标准 runner 用量免费且不限分钟数，因此 `nproc`
会自动使用 4 个构建线程。私有仓库的标准 Linux runner 当前提供 2 个 CPU，并消耗账户的
免费分钟额度。最终以 job 中实际的 `nproc` 结果为准；把 `THREADS` 人为设置为大于
runner CPU 数量不会增加可用 CPU，也通常不能缩短 LLVM 构建时间。

截至 2026 年 9 月，GitHub 官方仍将 `ubuntu-26.04` 标记为 Public Preview，而不是 GA
镜像；预览期可能出现镜像变化、暂时不稳定或排队问题。该状态不影响本地 Resolute 构建，
CI 失败时应先区分 runner 基础设施问题和项目编译问题。

每个 GitHub Actions job 都是独立环境。workflow 将 `NDK_TMP_DIR` 设置为
`${{ runner.temp }}`，由 `resolute-local-build.sh` 在该目录中选择 NDK。NDK r27d 目录通过
`actions/cache` 缓存：首次缓存未命中时会下载，后续构建可以直接恢复，避免每个 workflow
run 重复下载。LLVM 和完整构建目录不进入缓存，以避免大体积缓存占用免费存储额度，并
避免不同构建参数之间复用不兼容的 CMake 状态。

每个架构 job 一次构建以下三个 Android 产物：

```text
bpftools
bpftools-min
bpftrace-static
```

这些构建继续为 arm64 和 x86_64 分别上传对应产物。

三个目标作为同一个 Make 调用执行：

```bash
./scripts/resolute-local-build.sh bpftools bpftools-min bpftrace-static
```

完整包、精简包和静态 bpftrace 因而共用同一架构的一套完整 LLVM、BCC 和其他依赖，
Android 矩阵只需要 arm64、x86_64 两个 job。CI 的两个矩阵 job 是隔离环境，因此每个
job 各构建一次宿主 LLVM 和对应架构的 Android LLVM；本地 `all` 构建则让两个架构共享
同一套宿主 LLVM 工具。workflow 仍包含三个 `upload-artifact` 步骤，矩阵
展开后保持六个独立上传产物；每个上传内容同时附带该架构的 SHA-256 清单，保留期为
7 天。

构建完成后 CI 会先运行 `verify-artifacts.sh`，确认压缩包结构、包内所有 ELF 的架构和
共享库依赖闭包、Python TLS/pip 内容，以及静态 bpftrace 不依赖打包的
LLVM/Clang/BCC 动态库，验证通过才允许上传。

推送 `v*` tag 时，`.github/workflows/release.yml` 使用同样的双架构构建和验收流程，发布
六个产品文件及一个合并的 `SHA256SUMS` 到 GitHub Release。`CHANGELOG.md` 记录面向发布
用户的重要变化。

workflow 还包含两项免费额度保护：

- 同一分支或 Pull Request 有新提交时，自动取消仍在运行的旧构建；
- 只有构建相关的 Makefile、项目、工具链、sysroot、Resolute 脚本或 workflow 本身发生
  变化时才触发，纯 README/文档修改不会启动耗时的 Android 全量构建。

`black.yml` 和 `jdwp.yml` 不参与 Android LLVM/bpftrace 构建，因此可以独立选择 runner
版本；它们不影响 `bpftools.yml` 的 Ubuntu 26.04、API 35 构建结果。
