using System.Text;
using MahjongSoulNative;

if (args.Length != 3) throw new ArgumentException("Pass embedded Lua source path and raw-buffer directories for builds 25476613 and 26802421.");
var lua = File.ReadAllText(args[0]);
foreach (var (directory, module, hash, expectedBind) in new[]
{
    (args[1], SourcePatch.ViewModule, SourcePatch.ViewHash25476613, ""),
    (args[1], SourcePatch.BlockModule, SourcePatch.BlockHash25476613, "NativeTsumogiri.Bind(k,g)end;k:OnChoosed()"),
    (args[2], SourcePatch.ViewModule, SourcePatch.ViewHash26802421, ""),
    (args[2], SourcePatch.BlockModule, SourcePatch.BlockHash26802421, "NativeTsumogiri.Bind(l,h)end;l:OnChoosed()"),
})
{
    var raw = File.ReadAllBytes(Path.Combine(directory, hash + ".buffer"));
    Check(SourcePatch.TryApply(module, raw, lua, true, out var patched, out var diagnostic), $"{module} must match: {diagnostic}");
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
    else Check(text.Contains(expectedBind, StringComparison.Ordinal), "bind exact native object and input before choosing color");
    var otherModule = module == SourcePatch.ViewModule ? SourcePatch.BlockModule : SourcePatch.ViewModule;
    Check(!SourcePatch.TryApply(otherModule, raw, lua, true, out var swapped, out _) && swapped.SequenceEqual(raw), "known hash for a different module preserves original bytes");
    Check(!SourcePatch.TryApply(module, patched, lua, true, out var repeated, out _) && repeated.SequenceEqual(patched), "already patched content must not nest");
    var changed = raw.ToArray();
    changed[0] ^= 1;
    Check(!SourcePatch.TryApply(module, changed, lua, true, out var original, out _) && original.SequenceEqual(changed), "changed version preserves original bytes");
    Check(!SourcePatch.TryApply(module + "/other", raw, lua, true, out var unrelated, out _) && unrelated.SequenceEqual(raw), "unrelated name preserves original bytes");
    Check(!SourcePatch.TryApply(module, new byte[] { 0x1b, (byte)'L', (byte)'J', 2 }, lua, true, out _, out _), "bytecode never treated as source");
}
Console.WriteLine("PASS: actual captured sources from builds 25476613 and 26802421, module/hash allowlist, template ambiguity, config bytes, module return, idempotence, version mismatch, bytecode");
static void Check(bool condition, string description) { if (!condition) throw new Exception(description); }
