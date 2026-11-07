# Diagram notebook

Enable Mermaid and Graphviz in Markdown settings to render these offline examples.

```mermaid
flowchart LR
  A[Draft] --> B[Publish]
```

```dot
digraph {
  rankdir=LR;
  a [label="Source"];
  b [label="Preview"];
  a -> b;
}
```

```mermaid
sequenceDiagram
  Alice->>Bob: Review the draft
  Bob-->>Alice: Ready to publish
```

```mermaid
flowchart LR
  A["$$x^2$$"] --> B["$$\frac{1}{2}$$"]
```

The source stays ordinary Markdown. HTML/PDF/print carry rendered diagrams without
running Mermaid or Graphviz in the exported document.
