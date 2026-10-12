using System;
using System.IO;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;
using System.Management.Automation;
using System.Management.Automation.Runspaces;

[assembly: AssemblyTitle("vzc1's optimizations")]
[assembly: AssemblyProduct("vzc1's optimizations")]
[assembly: AssemblyDescription("Fortnite tweaks that actually do something")]
[assembly: AssemblyCompany("vzc1")]
[assembly: AssemblyCopyright("vzc1")]

namespace Vzc1Optimizations
{
    // Runs the app's PowerShell script inside this process. No files are dropped, nothing is downloaded.
    static class Program
    {
        [STAThread]
        static int Main(string[] args)
        {
            Environment.SetEnvironmentVariable("VZC1_ARGS", string.Join(" ", args));
            string script;
            using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("app.ps1"))
            using (StreamReader r = new StreamReader(s))
            {
                script = r.ReadToEnd();
            }

            try
            {
                InitialSessionState iss = InitialSessionState.CreateDefault();
                iss.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
                iss.ApartmentState = ApartmentState.STA;
                iss.ThreadOptions = PSThreadOptions.UseCurrentThread;

                using (Runspace rs = RunspaceFactory.CreateRunspace(iss))
                {
                    rs.ApartmentState = ApartmentState.STA;
                    rs.ThreadOptions = PSThreadOptions.UseCurrentThread;
                    rs.Open();
                    using (PowerShell ps = PowerShell.Create())
                    {
                        ps.Runspace = rs;
                        ps.AddScript(script);
                        ps.Invoke();
                    }
                }
                return 0;
            }
            catch (Exception e)
            {
                Exception inner = e;
                while (inner.InnerException != null) inner = inner.InnerException;
                MessageBox.Show("Something went wrong:\n\n" + inner.Message, "vzc1's optimizations", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
        }
    }
}
