using System.Text;
using MahjongSoulNative;

if (args.Length != 2) throw new ArgumentException("Pass current raw-buffer directory and embedded Lua source path.");
var lua = File.ReadAllText(args[1]);
foreach (var (module, hash) in new[] { (SourcePatch.ViewModule, SourcePatch.ViewHash), (SourcePatch.BlockModule, SourcePatch.BlockHash) })
{
    var raw = File.ReadAllBytes(Path.Combine(args[0], hash + ".buffer"));
    Check(SourcePatch.TryApply(module, raw, lua, true, out var patched, out _), "verified source must match");
    var text = Encoding.UTF8.GetString(patched);
    if (module == SourcePatch.ViewModule)
    {
        Check(text.EndsWith("return ViewPai", StringComparison.Ordinal), "preserve module return");
        Check(!text.Contains("__DEFAULT_ENABLED__", StringComparison.Ordinal), "resolve default config");
        Check(SourcePatch.TryApply(module, raw, lua, false, out var disabled, out _), "disabled config must match");
        Check(!patched.SequenceEqual(disabled), "config changes effective patch bytes");
        Check(!SourcePatch.TryApply(module, raw, lua + "__DEFAULT_ENABLED__", true, out var unchanged, out _)
            && unchanged.SequenceEqual(raw), "ambiguous embedded template fails closed");
    }
    else Check(text.Contains("NativeTsumogiri.Bind(k,g)", StringComparison.Ordinal), "bind exact native object and input");
    Check(!SourcePatch.TryApply(module, patched, lua, true, out var repeated, out _) && repeated.SequenceEqual(patched), "already patched content must not nest");
    var changed = raw.ToArray();changed[0] ^= 1;
    Check(!SourcePatch.TryApply(module, changed, lua, true, out var original, out _) && original.SequenceEqual(changed), "changed version preserves original bytes");
    Check(!SourcePatch.TryApply(module + "/other", raw, lua, true, out var unrelated, out _) && unrelated.SequenceEqual(raw), "unrelated name preserves original bytes");
    Check(!SourcePatch.TryApply(module, new byte[] { 0x1b, (byte)'L', (byte)'J', 2 }, lua, true, out _, out _), "bytecode never treated as source");
}
Console.WriteLine("PASS: actual captured sources, module/hash allowlist, template ambiguity, config bytes, module return, idempotence, version mismatch, bytecode");
static void Check(bool condition, string description) { if (!condition) throw new Exception(description); }
