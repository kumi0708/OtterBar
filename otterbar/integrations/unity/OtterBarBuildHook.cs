// OtterBar: Unity のビルド/スクリプトコンパイルを OtterBar に通知する。
// Assets/Editor/ 以下に置くだけで有効になる（macOS の Editor のみ）。
#if UNITY_EDITOR_OSX
using System.Diagnostics;
using System.Linq;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEditor.Compilation;

[InitializeOnLoad]
public static class OtterBarBuildHook
{
    // スクリプト保存ごとのコンパイルにも反応させるか（うるさければ false に）
    const bool ReactToScriptCompilation = true;

    static bool compilationHadErrors;

    static OtterBarBuildHook()
    {
        BuildPlayerWindow.RegisterBuildPlayerHandler(BuildPlayer);
        if (!ReactToScriptCompilation) return;
        CompilationPipeline.compilationStarted += _ =>
        {
            compilationHadErrors = false;
            Post("build.started");
        };
        CompilationPipeline.assemblyCompilationFinished += (_, messages) =>
        {
            if (messages.Any(m => m.type == CompilerMessageType.Error)) compilationHadErrors = true;
        };
        CompilationPipeline.compilationFinished += _ =>
            Post(compilationHadErrors ? "build.failed" : "build.succeeded");
    }

    static void BuildPlayer(BuildPlayerOptions options)
    {
        Post("build.started");
        BuildReport report = BuildPipeline.BuildPlayer(options);
        Post(report.summary.result == BuildResult.Succeeded ? "build.succeeded" : "build.failed");
    }

    static void Post(string eventName)
    {
        var startInfo = new ProcessStartInfo("/usr/bin/notifyutil", "-p com.otterbar." + eventName)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        Process.Start(startInfo)?.Dispose();
    }
}
#endif
