$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
class ArgvRecorder {
    static void Main(string[] args) {
        File.WriteAllLines(Environment.GetEnvironmentVariable("GIT_LINEAGE_TEST_ARGV"),
                           args, new UTF8Encoding(false));
    }
}
'@ -OutputAssembly (Join-Path $PSScriptRoot 'argv-recorder.exe') -OutputType ConsoleApplication
