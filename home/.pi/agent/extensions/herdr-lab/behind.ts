import { cli } from "./runtime.ts";

// Herdr 0.1 has no public no-activate launch option. Touch only the HWND
// belonging to the private app process; never force another app to take focus.
const API = `Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class LabWindow {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int w, int h, uint flags);
}
'@`;

export async function positionBehind(cwd: string, signal?: AbortSignal) {
	const run = cli("powershell.exe", cwd, process.env, signal);
	const script = (body: string) => run(["-NoProfile", "-NonInteractive", "-EncodedCommand", Buffer.from(`$ErrorActionPreference = 'Stop'\n${API}\n${body}`, "utf16le").toString("base64")]);
	const active = (await script("[LabWindow]::GetForegroundWindow().ToInt64()")).trim();
	if (!/^\d+$/.test(active)) throw new Error("Could not capture the active Windows window.");
	return async (pid: number) => {
		if (!Number.isSafeInteger(pid) || pid <= 0) throw new Error("Invalid lab window process ID.");
		await script(`$p = Get-Process -Id ${pid}
$p.Refresh()
$lab = $p.MainWindowHandle
if ($lab -eq [IntPtr]::Zero) { throw 'Lab window handle is not available.' }
$after = [IntPtr]${active}
if ($after -eq $lab -or -not [LabWindow]::IsWindow($after)) { $after = [IntPtr]1 }
if (-not [LabWindow]::SetWindowPos($lab, $after, 0, 0, 0, 0, 0x13)) { throw 'Could not put the lab behind the active window.' }`);
	};
}
