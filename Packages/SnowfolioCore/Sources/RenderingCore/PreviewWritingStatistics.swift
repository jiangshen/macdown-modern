/// Read-only snapshot of the committed DOM, evaluated in WebKit's isolated world.
/// No document scripts, layout queries, mutation observer or polling are needed.
public enum PreviewWritingStatistics {
  public static let capture = """
    const root = document.getElementById('preview-content');
    if (!root) return null;
    const runs = [], stack = [{node:root, group:0}];
    let nextGroup = 0;
    while (stack.length) {
      const {node,group} = stack.pop();
      if (node.nodeType === Node.TEXT_NODE || node.nodeType === Node.CDATA_SECTION_NODE) {
        if (node.nodeValue) runs.push({text:node.nodeValue, wordGroup:group});
        continue;
      }
      if (node.nodeType !== Node.ELEMENT_NODE && node.nodeType !== Node.DOCUMENT_FRAGMENT_NODE) continue;
      const tag = node.nodeName.toUpperCase();
      if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'HEAD') continue;
      let childGroup = group;
      if (tag === 'CODE') {
        if (node.parentElement?.nodeName.toUpperCase() === 'PRE') childGroup = -1;
        else if (group === 0) childGroup = ++nextGroup;
      }
      // Isolated diagram labels live in an open shadow root after preview commit.
      const children = (node.shadowRoot ?? node).childNodes;
      for (let i = children.length - 1; i >= 0; i--) stack.push({node:children[i],group:childGroup});
    }
    return JSON.stringify(runs);
    """
}
