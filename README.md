# 雀魂客户端手摸切显示插件

版本 0.3.0，已在 Windows Steam 雀魂 4.0.35（Unity 2022.3.62f2c1、x86 IL2CPP）验收。

直接沿用原生弃牌对象和摸切标记：普通摸切变灰，手切保持原样；立直横牌、鸣牌移除、下一局和窗口缩放沿用原生行为。牌谱回放保留客户端已有的摸切显示。

- 默认开启；F8 开关并保存设置，重新开启会刷新已有弃牌。

插件不读取屏幕、不模拟操作，不提供额外悬浮层。

## 一键安装

先退出雀魂并完成退出确认，然后在 PowerShell 中粘贴这一行即可安装，**无需预先下载 Release、无需安装包管理器**：

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/ChildeRolando/majsoul_moqie/main/install.ps1)))
```

这一行从公开仓库运行安装脚本，自动定位 Steam 雀魂、下载并校验 BepInEx 和插件，再放入游戏目录。已有配置保留。若需要指定游戏目录：

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/ChildeRolando/majsoul_moqie/main/install.ps1))) -GameDirectory "D:\SteamLibrary\steamapps\common\MahjongSoul"
```

也可以从 [Releases](https://github.com/ChildeRolando/majsoul_moqie/releases/tag/v0.3.0) 下载 `majsoul_moqie-setup-0.3.0.exe`，**双击即可安装，无需解压**。EXE 内嵌相同安装脚本，运行时联网下载加载器和插件；不需要安装 .NET SDK 或 Python。命令行执行时同样支持 `-GameDirectory`、`-WhatIf` 和离线压缩包参数。

### 保留的 ZIP 安装方式

1. 退出雀魂，完成退出确认。
2. 从 [Releases](https://github.com/ChildeRolando/majsoul_moqie/releases/tag/v0.3.0) 下载 `native-tsumogiri-0.3.0-installer.zip`，解压到任意目录。
3. 双击 `install.cmd`。脚本自动从 Steam 库定位雀魂，下载已验收的 BepInEx IL2CPP x86 build 788，并安装加载器和插件。
4. 正常启动雀魂即可。首次启动 BepInEx 会生成游戏接口，可能需要较长时间；以后随客户端自动加载。默认开启，F8 可开关。

不需要 .NET SDK 或 Python；支持 Windows 自带的 PowerShell 5.1。通常无需管理员权限；游戏目录无写入权限时，改用有权限的终端执行。脚本不会自动启动游戏。

也可以在解压目录通过 PowerShell 执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

自动定位失败或检测到多份安装时，指定**包含 Jantama_MahjongSoul.exe 的游戏根目录**：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -GameDirectory "D:\SteamLibrary\steamapps\common\MahjongSoul"
```

命令提示符中也可执行 `install.cmd -GameDirectory "D:\SteamLibrary\steamapps\common\MahjongSoul"`。使用 `-WhatIf` 可先预览目标，不下载或写入文件。

脚本校验加载器压缩包、插件压缩包和 DLL 的 SHA256，只支持已验收的 x86 IL2CPP 客户端。重复安装保留已有设置和其他插件；同版本加载器文件直接复用。遇到不同版本或被修改的加载器会停止，不自动覆盖。替换旧版插件时会备份，写入失败会回滚本轮新增文件。下载和备份保留在终端显示的临时目录。

仓库和安装包公开下载，无需登录 GitHub，也不需要 GitHub CLI。安装包已附带插件；若仅下载脚本，脚本会自动下载插件包，也可用 `-PluginArchive` 指定已下载的原始发行包。BepInEx 从 [官方构建站](https://builds.bepinex.dev/projects/bepinex_be) 下载，需要联网；可提前下载匹配的 build 788，用以下命令离线安装：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -GameDirectory "D:\SteamLibrary\steamapps\common\MahjongSoul" -LoaderArchive ".\BepInEx-Unity.IL2CPP-win-x86-6.0.0-be.788+5b766a3.zip" -PluginArchive ".\native-tsumogiri-0.3.0-release.zip"
```

已有 F8 设置不会被重置，位于 BepInEx/config/local.mahjongsoul.native-tsumogiri.cfg。

## 手动安装与卸载

退出游戏，安装匹配的 BepInEx IL2CPP Windows x86 build 788。下载原始 `native-tsumogiri-0.3.0-release.zip`，将其中 BepInEx 目录合并到游戏根目录。原始发行包不包含加载器；一键安装脚本负责下载它。

卸载时退出游戏，删除 BepInEx/plugins/NativeTsumogiri/MahjongSoulNative.dll；共享的 BepInEx 环境可以保留。

客户端更新导致目标模块内容改变时，插件拒绝修改未知模块。诊断记录位于游戏目录 BepInEx/native-tsumogiri，加载日志位于 BepInEx/LogOutput.log。

## 开发与验证

项目仅保留正式源码、必要回归测试和发行包。构建需要 .NET SDK 8，以及已初始化 BepInEx 的游戏目录（含生成的 interop 程序集）。在本目录执行：

```powershell
dotnet build ./src/MahjongSoulNative.csproj -c Release -p:GameDirectory='<游戏目录>'
python -m pip install --target ./tools/python lupa
python ./tests/test_native_tsumogiri.py
dotnet run --project ./tests/SourcePatchChecks -- '<原始 buffer 目录>' './lua/native-tsumogiri.lua'
./build-package.ps1 -Tag '<新包标签>'
./build-installer.ps1 # 使用 Windows 自带 .NET Framework 编译器生成 EXE 安装器
# 安装器文件操作回归：使用真实的固定版本压缩包，在临时模拟游戏目录测试
./tests/test_install.ps1 -LoaderArchive '<BepInEx 788 压缩包>' -PluginArchive './dist/native-tsumogiri-0.3.0-release.zip'
./tests/test_entrypoints.ps1 -LoaderArchive '<BepInEx 788 压缩包>' -PluginArchive '<原始发行包绝对路径>'
```

SourcePatchChecks 使用本机诊断记录里的原始 ViewPai、Block_QiPai buffer；发行包不包含客户端 Lua 源码。重新构建的包需单独验收，不能继承现有 DLL 的人工验收。

已完成的检查和发行 DLL 校验值见 [ACCEPTANCE.md](ACCEPTANCE.md)。

