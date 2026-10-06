using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using BepInEx;
using BepInEx.Configuration;
using BepInEx.Unity.IL2CPP;
using HarmonyLib;
using Il2CppInterop.Runtime.InteropTypes.Arrays;
using LuaInterface;
using UnityEngine;

namespace MahjongSoulNative;

[BepInPlugin("local.mahjongsoul.native-tsumogiri", "Native Tsumogiri", "0.3.0")]
public sealed class Plugin : BasePlugin
{
    private static Plugin? instance;
    private readonly HashSet<string> seen = new(StringComparer.Ordinal);
    private readonly object gate = new();
    private string evidenceDirectory = "";
    private Harmony? harmony;
    private static IntPtr luaState;
    private static bool viewPatched;
    private static bool blockPatched;
    private static int luaThread;
    private ConfigEntry<bool> enabled = null!;
    private string luaPatch = "";
    private string? lastSnapshot;

    public override void Load()
    {
        luaState = IntPtr.Zero;
        viewPatched = false;
        blockPatched = false;
        instance = this;
        enabled = Config.Bind("Display", "Enabled", true, "Dim native tsumogiri river objects. F8 toggles and saves this setting.");
        using (var stream = typeof(Plugin).Assembly.GetManifestResourceStream("native-tsumogiri.lua")!)
        using (var reader = new StreamReader(stream, Encoding.UTF8)) luaPatch = reader.ReadToEnd();
        evidenceDirectory = Path.Combine(Paths.BepInExRootPath, "native-tsumogiri", "probe-" + DateTime.UtcNow.ToString("yyyyMMdd-HHmmss"));
        Directory.CreateDirectory(evidenceDirectory);
        harmony = new Harmony("local.mahjongsoul.native-tsumogiri");
        var expected = new[] { typeof(IntPtr), typeof(Il2CppStructArray<byte>), typeof(int), typeof(string) };
        // P0 observed luaL_loadbuffer only. Hook one boundary to avoid nesting.
        foreach (var name in new[] { "luaL_loadbuffer" })
        {
            var method = typeof(LuaDLL).GetMethod(name, BindingFlags.Public | BindingFlags.Static, null, expected, null);
            if (method == null || method.ReturnType != typeof(int))
            {
                Log.LogWarning("Signature mismatch; probe skipped: " + name);
                continue;
            }
            harmony.Patch(method, prefix: new HarmonyMethod(typeof(Plugin), nameof(Observe)));
            Log.LogInfo("Verified Lua boundary attached: " + method);
        }
        var close = typeof(LuaDLL).GetMethod("lua_close", BindingFlags.Public | BindingFlags.Static,
            null, new[] { typeof(IntPtr) }, null);
        if (close == null || close.ReturnType != typeof(void))
        {
            harmony.UnpatchSelf();
            Log.LogWarning("Lua close signature mismatch; native display hooks disabled");
            return;
        }
        harmony.Patch(close, prefix: new HarmonyMethod(typeof(Plugin), nameof(StateClosing)));
        Log.LogInfo("Lua lifetime guard attached: " + close);
        AddComponent<DisplayKeys>();
        Log.LogInfo("Probe evidence: " + evidenceDirectory);
    }

    private static void StateClosing(IntPtr __0)
    {
        if (__0 != luaState) return;
        // Stop Unity Update commands before the native Lua state is freed.
        luaState = IntPtr.Zero;
        viewPatched = false;
        blockPatched = false;
        instance?.Log.LogInfo("Tracked Lua state closing; display commands stopped");
    }

    private static void Observe(MethodBase __originalMethod, IntPtr __0, ref Il2CppStructArray<byte> __1, ref int __2, string __3)
    {
        // Save actual original bytes before considering a source patch.
        try
        {
            instance?.Record(__originalMethod.Name, __1, __2, __3);
            if (__3 != SourcePatch.ViewModule && __3 != SourcePatch.BlockModule) return;
            if (__2 < 0 || __2 > __1.Length || __2 > 4 * 1024 * 1024) return;
            var original = new byte[__2];
            for (var i = 0; i < __2; i++) original[i] = __1[i];
            var hash = Convert.ToHexString(SHA256.HashData(original)).ToLowerInvariant();
            if (instance == null) return;
            if (luaState != IntPtr.Zero && (luaState != __0 || luaThread != Environment.CurrentManagedThreadId))
            {
                instance.Log.LogWarning("Unexpected Lua state/thread; original module preserved");
                return;
            }
            if (!SourcePatch.TryApply(__3, original, instance.luaPatch, instance.enabled.Value, out var patched, out var diagnostic))
            {
                instance.Log.LogWarning("Original module preserved: " + diagnostic);
                return;
            }
            File.WriteAllBytes(Path.Combine(instance.evidenceDirectory, hash + "." + SourcePatch.Version + ".lua"), patched);
            File.AppendAllText(Path.Combine(instance.evidenceDirectory, "patches.jsonl"), JsonSerializer.Serialize(new
                {
                    module = __3, originalSha256 = hash,
                    patchedSha256 = Convert.ToHexString(SHA256.HashData(patched)).ToLowerInvariant(),
                    patchVersion = SourcePatch.Version, enabled = instance.enabled.Value, thread = Environment.CurrentManagedThreadId
                }) + Environment.NewLine);
            var replacement = new Il2CppStructArray<byte>(patched.Length);
            for (var i = 0; i < patched.Length; i++) replacement[i] = patched[i];
            __1 = replacement;
            __2 = patched.Length;
            luaState = __0;
            luaThread = Environment.CurrentManagedThreadId;
            if (__3 == SourcePatch.ViewModule) viewPatched = true;
            if (__3 == SourcePatch.BlockModule) blockPatched = true;
            instance.Log.LogInfo(diagnostic);
        }
        catch (Exception ex) { instance?.Log.LogWarning("Probe failed; original execution preserved: " + ex.Message); }
    }

    public sealed class DisplayKeys : MonoBehaviour
    {
        private long nextSnapshot;
        public DisplayKeys(IntPtr pointer) : base(pointer) { }
        public void Update()
        {
            var toggle = Input.GetKeyDown(KeyCode.F8);
            var snapshot = Input.GetKeyDown(KeyCode.F10);
            if (!viewPatched || !blockPatched || luaState == IntPtr.Zero || Environment.CurrentManagedThreadId != luaThread)
            {
                if (toggle || snapshot) instance?.Log.LogWarning("Display unavailable: both verified modules and the Lua thread are required");
                return;
            }
            if (toggle && RunCommand("return NativeTsumogiri and NativeTsumogiri.Toggle and NativeTsumogiri.Toggle() or 'module not executed yet'", "toggle", out var result))
            {
                if (instance != null && (result.StartsWith("enabled=true", StringComparison.Ordinal) || result.StartsWith("enabled=false", StringComparison.Ordinal)))
                {
                    instance.enabled.Value = result.StartsWith("enabled=true", StringComparison.Ordinal);
                    instance.Config.Save();
                }
            }
            var now = Environment.TickCount64;
            if (snapshot || now >= nextSnapshot)
            {
                nextSnapshot = now + 2000;
                RunCommand("return NativeTsumogiri and NativeTsumogiri.Snapshot and NativeTsumogiri.Snapshot() or 'module not executed yet'", "snapshot", out _);
            }
        }
    }

    private static bool RunCommand(string source, string kind, out string result)
    {
        result = "";
        var top = LuaDLL.lua_gettop(luaState);
        try
        {
            var bytes = Encoding.UTF8.GetBytes(source);
            var buffer = new Il2CppStructArray<byte>(bytes.Length);
            for (var i = 0; i < bytes.Length; i++) buffer[i] = bytes[i];
            var status = LuaDLL.luaL_loadbuffer(luaState, buffer, bytes.Length, "@NativeTsumogiriCommand");
            if (status == 0) status = LuaDLL.lua_pcall(luaState, 0, 1, 0);
            result = LuaDLL.lua_tostring(luaState, -1) ?? "";
            if (status != 0) instance?.Log.LogWarning("Native display Lua error: " + result);
            var changed = kind != "snapshot" || instance?.lastSnapshot != result;
            if (instance != null && changed)
            {
                if (kind == "snapshot") instance.lastSnapshot = result;
                instance.Log.LogInfo("Native display " + kind + ": " + result.Split('\n')[0]);
                File.AppendAllText(Path.Combine(instance.evidenceDirectory, "commands.jsonl"),
                    JsonSerializer.Serialize(new { utc = DateTime.UtcNow, kind, status, result }) + Environment.NewLine);
            }
            return status == 0;
        }
        catch (Exception ex)
        {
            instance?.Log.LogWarning("Native display command failed: " + ex.Message);
            return false;
        }
        finally { LuaDLL.lua_settop(luaState, top); }
    }

    private void Record(string entry, Il2CppStructArray<byte> buffer, int size, string module)
    {
        // Only static display/binding modules; never dump login or session objects.
        if (module != SourcePatch.ViewModule && module != SourcePatch.BlockModule
            && module != "@Game/MJ/ViewPlayer" && module != "@Game/MJ/ViewPlayer_Me"
            && module != "@Game/MJ/ViewPlayer_Other") return;
        if (buffer == null || size < 0 || size > buffer.Length || size > 4 * 1024 * 1024)
        {
            Log.LogWarning("Invalid/oversized Lua buffer; skipped");
            return;
        }
        var bytes = new byte[size];
        for (var i = 0; i < size; i++) bytes[i] = buffer[i];
        var hash = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
        var format = size >= 3 && bytes[0] == 0x1b && bytes[1] == (byte)'L' && bytes[2] == (byte)'J' ? "luajit-bytecode"
            : size >= 4 && bytes[0] == 0x1b && bytes[1] == (byte)'L' && bytes[2] == (byte)'u' && bytes[3] == (byte)'a' ? "lua-bytecode"
            : IsUtf8(bytes) ? "utf8" : "binary";
        lock (gate)
        {
            if (!seen.Add(entry + "\0" + module + "\0" + hash)) return;
            var saved = hash + ".buffer";
            File.WriteAllBytes(Path.Combine(evidenceDirectory, saved), bytes);
            File.AppendAllText(Path.Combine(evidenceDirectory, "loads.jsonl"), JsonSerializer.Serialize(new
            {
                utc = DateTime.UtcNow, entry, module, size, sha256 = hash, format, saved,
                thread = Environment.CurrentManagedThreadId, mode = "original-buffer"
            }) + Environment.NewLine);
        }
    }

    private static bool IsUtf8(byte[] bytes)
    {
        try { _ = new UTF8Encoding(false, true).GetString(bytes); return !bytes.Contains((byte)0); }
        catch (DecoderFallbackException) { return false; }
    }

    public override bool Unload()
    {
        if (viewPatched && luaState != IntPtr.Zero)
        {
            if (Environment.CurrentManagedThreadId != luaThread)
            {
                Log.LogWarning("Unload requires the Lua thread; restart the client to unload safely");
                return false;
            }
            if (!RunCommand("return NativeTsumogiri and NativeTsumogiri.Uninstall and NativeTsumogiri.Uninstall() or 'display not installed'", "uninstall", out _)) return false;
        }
        harmony?.UnpatchSelf();
        luaState = IntPtr.Zero;
        viewPatched = false;
        blockPatched = false;
        instance = null;
        return true;
    }
}
