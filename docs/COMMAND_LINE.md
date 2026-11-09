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

Open **Snowfolio → Settings → General → Terminal** to install a symbolic link
using the native folder chooser. Choose an existing folder in your shell’s `PATH`
to run `snowfolio` by name. **Copy Command** supplies a fully quoted absolute command
that also works when the selected folder is outside `PATH`.

Settings remembers the selected link and its target. If you move the app, **Update**
repairs that recorded link. **Remove** removes only the recorded link, preserving
the app and documents. An occupied location is reported so you can choose a different
folder. No shell configuration or existing MacDown command is replaced automatically.
The native installation controls are a new candidate; actual-app chooser and visual
acceptance are tracked in the validation ledger.
