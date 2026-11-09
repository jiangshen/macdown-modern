# Snowfolio from Terminal

The modern app includes an Apple Silicon command-line tool at
`Snowfolio.app/Contents/Helpers/snowfolio`. Its packaged document flow is under
validation; see [the current evidence](validation/command-line.json).
The build does not install a command into your shell's search path.

Run the helper inside the app you want to open. For example, if that app is in
`/Applications`:

```sh
"/Applications/Snowfolio.app/Contents/Helpers/snowfolio" notes.md
"/Applications/Snowfolio.app/Contents/Helpers/snowfolio" first.md second.md
printf '# Draft\n\nHello.\n' | "/Applications/Snowfolio.app/Contents/Helpers/snowfolio"
```

Relative paths use your Terminal's current folder. Repeated paths open one
document. A missing file is created empty; parent folders must already exist.
Existing files are never replaced to create a new document.

Piped input must be valid UTF-8. It opens in a separate unsaved document and keeps
its original byte-order mark and line endings when saved. The tool waits until
the producer finishes, so delayed input is supported. Files and piped input can
be supplied in the same command.

Use `-h`/`--help` for help and `-v`/`--version` for the app version. Options come
before the first filename. Use `--` to open a filename beginning with a dash:

```sh
"/Applications/Snowfolio.app/Contents/Helpers/snowfolio" -- --draft.md
```

After the first filename, subsequent arguments are filenames, including `--help`.
Unknown leading options fail with exit status 64. Invalid input or a failed app
connection returns a nonzero status. Success means the selected app acknowledged
the request; document-reading errors are shown in the app. Saving remains a
normal document action in Snowfolio.

A symbolic link to the bundled helper is supported. Keep the app in its final
location before creating one. Shell installation controls are still pending;
no system command or existing MacDown link is replaced automatically.
