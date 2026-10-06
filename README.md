# 雀魂原生摸切暗化

版本 0.3.0，已在 Windows Steam 雀魂 4.0.35（Unity 2022.3.62f2c1、x86 IL2CPP）验收。

直接沿用原生弃牌对象和摸切标记：普通摸切变灰，手切保持原样；鼠标高亮、立直横牌、鸣牌移除、下一局和窗口缩放沿用原生行为。牌谱回放保留客户端已有的摸切显示。

- 默认开启；F8 开关并保存设置，重新开启会刷新已有弃牌。
- F10 记录诊断快照。插件不读取屏幕、不模拟操作，不提供额外悬浮层。

## 安装与卸载

退出雀魂并完成退出确认。安装与客户端架构匹配的 [BepInEx IL2CPP Windows x86](https://builds.bepinex.dev/projects/bepinex_be)，本次验收使用 build 788。从 [Releases](https://github.com/ChildeRolando/majsoul_moqie/releases/tag/v0.3.0) 下载并解压 native-tsumogiri-0.3.0-release.zip，把其中 BepInEx 目录合并到游戏根目录，随后启动游戏。

发行包只包含插件 DLL、说明和校验清单；BepInEx 运行环境须单独安装。已有设置不会被发行包覆盖。F8 的设置保存在 BepInEx/config/local.mahjongsoul.native-tsumogiri.cfg。

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
```

SourcePatchChecks 使用本机诊断记录里的原始 ViewPai、Block_QiPai buffer；发行包不包含客户端 Lua 源码。重新构建的包需单独验收，不能继承现有 DLL 的人工验收。

已完成的检查和发行 DLL 校验值见 [ACCEPTANCE.md](ACCEPTANCE.md)。

