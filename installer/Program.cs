using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;

// Windows .NET Framework bootstrapper. Embed the same reviewed PowerShell installer.
internal static class Program
{
    private static string Quote(string value)
    {
        var result = new StringBuilder("\"");
        int slashes = 0;
        foreach (char character in value)
        {
            if (character == '\\') { slashes++; continue; }
            if (character == '"')
                result.Append('\\', slashes * 2 + 1).Append(character);
            else
                result.Append('\\', slashes).Append(character);
            slashes = 0;
        }
        return result.Append('\\', slashes * 2).Append('"').ToString();
    }

    private static int Main(string[] args)
    {
        int code = 1;
        try
        {
            string work = Path.Combine(Path.GetTempPath(), "majsoul-moqie-exe-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(work);
            string script = Path.Combine(work, "install.ps1");
            using (Stream input = Assembly.GetExecutingAssembly().GetManifestResourceStream("install.ps1"))
            using (Stream output = File.Create(script))
            {
                if (input == null) throw new InvalidOperationException("Embedded installer missing.");
                input.CopyTo(output);
            }
            var command = new StringBuilder("-NoProfile -ExecutionPolicy Bypass -File ");
            command.Append(Quote(script));
            foreach (string argument in args) command.Append(' ').Append(Quote(argument));
            string shell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
            using (Process process = Process.Start(new ProcessStartInfo(shell, command.ToString()) { UseShellExecute = false }))
            {
                if (process == null) throw new InvalidOperationException("Could not start PowerShell.");
                process.WaitForExit();
                code = process.ExitCode;
            }
        }
        catch (Exception error) { Console.Error.WriteLine(error.Message); }
        // Leave the result visible for interactive no-argument launches.
        if (args.Length == 0 && !Console.IsInputRedirected)
        {
            Console.WriteLine(code == 0 ? "Installation complete. Press any key to close." : "Installation failed. Press any key to close.");
            Console.ReadKey(true);
        }
        return code;
    }
}
