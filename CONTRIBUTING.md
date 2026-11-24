# Contributing

## Layout

- `Sources/tca-navmap/`: the tool, one executable target.
  - `Extractor.swift`: two swift-syntax passes over every file. The first finds reducers and the views that hold a store; the second collects facts (slots, assignments, sends, presentations) and attributes each to a reducer.
  - `Model.swift`: those facts, and the `Configuration` that carries what syntax cannot tell.
  - `Graph.swift`: resolves the facts across files into the output model, and searches for the controls that reach each destination.
  - `Markdown.swift`: the Markdown rendering. The JSON is the output model encoded as it stands.
  - `Options.swift`, `SourceFiles.swift`, `main.swift`: the command line.
- `Tests/NavigationMapTests/`: the tests. Every one runs on source text held in the test file, with made-up paths; none reads the disk except the source-discovery test, which builds its own temporary directory.
- `Example/Sources/`: a small app's source for trying the tool. It is read, never built, and is not part of the package.
- `Example/navigation-map/`: the map of the example, committed so the README can link to it.

## Running the tests

```bash
swift test
```

## Changing what is extracted

Add the smallest source that shows the pattern to a test, assert on the map, then teach the extractor. After any change to the extractor or the renderer, regenerate the example's map with the command in the README and commit the difference: it is the one end-to-end check in the repository, and the diff shows what your change does to real output.

Output must stay deterministic. Anything gathered into a set or dictionary is sorted before it is written, so that regenerating from unchanged source gives identical bytes.

## Style

- Swift 6 language mode. swift-syntax is the only dependency.
- Comments say why, and show the source pattern a piece of code is there to match.
- Docs: say what something does and what it costs; when a number is quoted, say how it was measured.
