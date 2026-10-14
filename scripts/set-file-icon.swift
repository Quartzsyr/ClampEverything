import AppKit
let icon = NSImage(contentsOfFile: CommandLine.arguments[1])!
guard NSWorkspace.shared.setIcon(icon, forFile: CommandLine.arguments[2], options: []) else {
    fputs("Could not set installer icon\n", stderr); exit(1)
}
