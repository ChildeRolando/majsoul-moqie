using System.Security.Cryptography;
using System.Text;

namespace MahjongSoulNative;

internal static class SourcePatch
{
    internal const string Version = "native-v1";
    internal const string ViewModule = "@Game/MJ/ViewPai";
    internal const string BlockModule = "@Game/MJ/Block_QiPai";
    internal const string ViewHash25476613 = "af97809905789b695fdd34d0415aa1d5eaa78240c48bd2d7b20f4e555b9b1d94";
    internal const string BlockHash25476613 = "d3c456d82d76de6b61b0a6e1fb983913205bf415dcb23bc421fa54c40ae6e5cc";
    internal const string ViewHash26802421 = "9ca196d20456c0c6bed438cdf7b4da6d02f3deed491151c011f71bca1db821ca";
    internal const string BlockHash26802421 = "44d2f901f9016679c5d8eb99d5beacab661d7ee5fa76b5f18a264807214d635d";

    internal static bool TryApply(string module, byte[] original, string lua, bool enabled,
        out byte[] patched, out string diagnostic)
    {
        patched = original;
        diagnostic = "module not allowed";
        if (module != ViewModule && module != BlockModule) return false;
        if (original.Length > 4 * 1024 * 1024) { diagnostic = "buffer exceeds 4 MiB"; return false; }
        var hash = Convert.ToHexString(SHA256.HashData(original)).ToLowerInvariant();
        var verified = module == ViewModule
            ? hash is ViewHash25476613 or ViewHash26802421
            : hash is BlockHash25476613 or BlockHash26802421;
        if (!verified) { diagnostic = "hash mismatch: " + hash; return false; }
        string source;
        try { source = new UTF8Encoding(false, true).GetString(original); }
        catch (DecoderFallbackException) { diagnostic = "not UTF-8 source"; return false; }
        if (module == ViewModule)
        {
            const string anchor = "return ViewPai";
            if (!source.EndsWith(anchor, StringComparison.Ordinal) || !Unique(source, anchor))
            { diagnostic = "ViewPai return anchor mismatch"; return false; }
            if (!Unique(lua, "__DEFAULT_ENABLED__"))
            { diagnostic = "embedded patch template mismatch"; return false; }
            lua = lua.Replace("__DEFAULT_ENABLED__", enabled ? "true" : "false", StringComparison.Ordinal);
            source = source[..^anchor.Length] + "\n" + lua + "\n" + anchor;
        }
        else
        {
            var (setup, choose, arguments) = hash == BlockHash25476613
                ? ("if DesktopMgr.Inst:get_show_moqie()then k.ismoqie=g end;k.isreveal=i;", "k:OnChoosed()", "k,g")
                : ("if DesktopMgr.Inst:get_show_moqie()then l.ismoqie=h end;l.isreveal=j;", "l:OnChoosed()", "l,h");
            var anchor = setup + choose;
            if (!Unique(source, anchor)) { diagnostic = "binding anchor count mismatch"; return false; }
            var bind = "if NativeTsumogiri and NativeTsumogiri.Bind then NativeTsumogiri.Bind(" + arguments + ")end;";
            source = source.Replace(anchor, setup + bind + choose, StringComparison.Ordinal);
        }
        patched = Encoding.UTF8.GetBytes(source);
        diagnostic = "matched " + module + " original=" + hash + " patch=" + Version;
        return true;
    }

    private static bool Unique(string text, string anchor)
    {
        var first = text.IndexOf(anchor, StringComparison.Ordinal);
        return first >= 0 && text.IndexOf(anchor, first + anchor.Length, StringComparison.Ordinal) < 0;
    }
}
