import Foundation

public enum PreviewHTML {
  public static func document(
    body: String = "", remoteImages: Bool = false,
    title: String = "", includeStyles: Bool = true
  ) -> String {
    let imageSources = remoteImages ? "mdasset: data: https:" : "mdasset: data:"
    return """
      <!doctype html><html><head><meta charset="utf-8">
      <title>\(escapeText(title))</title>
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src \(imageSources); style-src 'unsafe-inline' mdasset:; font-src mdasset: data:; script-src 'none'; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
      \(includeStyles ? stylesheet : "")</head><body><main id="preview-content">\(body)</main></body></html>
      """
  }

  private static func escapeText(_ value: String) -> String {
    value.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&#39;")
  }

  private static let stylesheet = """
    <style>
      :root { color-scheme: light dark; --border: #d9e1e8; --muted: #596875; --code: #f1f5f8; }
      body { margin: 0; font: 16px/1.65 -apple-system, BlinkMacSystemFont, sans-serif; overflow-wrap: anywhere; }
      main { max-width: 76ch; padding: 32px 36px 80px; margin: auto; }
      h1,h2,h3,h4,h5,h6 { line-height: 1.25; scroll-margin-top: 24px; }
      h1 { font-size: 2em; } h2 { margin-top: 1.6em; }
      a { color: #247aa9; } blockquote { margin-left: 0; padding-left: 1em; border-left: 3px solid var(--border); color: var(--muted); }
      pre,code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .9em; }
      code { background: var(--code); border-radius: 4px; padding: .12em .28em; }
      pre { overflow-x: auto; background: var(--code); border-radius: 10px; padding: 16px; }
      pre code { padding: 0; background: transparent; white-space: pre; }
      img { max-width: 100%; height: auto; } table { border-collapse: collapse; display: block; overflow-x: auto; }
      th,td { border: 1px solid var(--border); padding: .45em .8em; } th { background: var(--code); }
      hr { border: 0; border-top: 1px solid var(--border); margin: 2em 0; }
      input[type=checkbox] { margin-right: .5em; } .footnotes { font-size: .9em; }
      @media (prefers-color-scheme: dark) { :root { --border: #3b4650; --muted: #aebbc5; --code: #232c34; } a { color: #7fc8ef; } }
      @media print {
      :root { color-scheme: light; --border: #d9e1e8; --muted: #596875; --code: #f1f5f8; }
      body { color: #000; background: #fff; } main { max-width: none; padding: 0; }
      pre,pre code { white-space: pre-wrap; overflow-wrap: anywhere; }
      h1,h2,h3,h4,h5,h6 { break-after: avoid; } tr { break-inside: avoid; }
      table { display: table; width: 100%; } thead { display: table-header-group; }
      }
      </style>
    """

  /// Only this trusted function runs in WKWebView's isolated client world. Document
  /// scripts remain disabled. The HTML argument is data, never executable interpolation.
  public static let patch = """
    const root = document.getElementById('preview-content');
    if (!root) return false;
    const incoming = document.createElement('main');
    incoming.innerHTML = html;
    const anchor = [...root.querySelectorAll('[data-sourcepos]')].find(e => e.getBoundingClientRect().bottom > 0);
    const anchorTop = anchor ? anchor.getBoundingClientRect().top : 0;
    const previousY = window.scrollY;
    function sync(oldParent, newParent) {
      const next = [...newParent.childNodes];
      for (let index = 0; index < next.length; index++) {
        const wanted = next[index], existing = oldParent.childNodes[index];
        if (!existing) { oldParent.appendChild(wanted.cloneNode(true)); continue; }
        if (existing.isEqualNode(wanted)) continue;
        if (existing.nodeType !== wanted.nodeType || existing.nodeName !== wanted.nodeName) {
          oldParent.replaceChild(wanted.cloneNode(true), existing); continue;
        }
        if (wanted.nodeType === Node.TEXT_NODE || wanted.nodeType === Node.COMMENT_NODE) {
          existing.nodeValue = wanted.nodeValue; continue;
        }
        for (const attr of [...existing.attributes]) if (!wanted.hasAttribute(attr.name)) existing.removeAttribute(attr.name);
        for (const attr of [...wanted.attributes]) if (existing.getAttribute(attr.name) !== attr.value) existing.setAttribute(attr.name, attr.value);
        sync(existing, wanted);
      }
      while (oldParent.childNodes.length > next.length) oldParent.lastChild.remove();
    }
    sync(root, incoming);
    if (anchor && anchor.isConnected) window.scrollBy(0, anchor.getBoundingClientRect().top - anchorTop);
    else window.scrollTo(0, previousY);
    return true;
    """
}
