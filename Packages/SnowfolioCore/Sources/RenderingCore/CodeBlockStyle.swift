enum CodeBlockStyle {
  static let css = """
    .md-code-block { margin-block: .8em; }
    .md-code-block > pre { margin-block: 0; }
    .md-code-label {
      padding: .35em .8em; text-align: end; overflow-wrap: anywhere; white-space: pre-wrap;
      font-family: -apple-system, BlinkMacSystemFont, sans-serif; font-size: .8em;
      color: var(--muted, inherit);
    }
    pre[data-code-numbered] > code { display: block; }
    pre[data-code-numbered] .md-code-line {
      display: inline-block; position: relative; min-inline-size: 100%; min-block-size: 1lh; box-sizing: border-box;
      padding-inline-start: calc(var(--md-code-gutter) + 1ch); vertical-align: top;
    }
    pre[data-code-numbered] .md-code-number {
      position: absolute; display: block; inset-inline-start: 0; inset-block-start: 0;
      inline-size: var(--md-code-gutter); box-sizing: border-box; padding-inline-end: .7ch;
      border-inline-end: 1px solid currentColor; text-align: end; opacity: .6;
      font-variant-numeric: tabular-nums; pointer-events: none; user-select: none;
    }
    pre[data-code-numbered] .md-code-number::before { content: attr(data-line); }
    @media (prefers-contrast: more) { pre[data-code-numbered] .md-code-number { opacity: 1; } }
    """
}
