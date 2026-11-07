import Foundation
import MathCore

public enum PreviewHTML {
  public static func document(
    body: String = "", remoteImages: Bool = false,
    title: String = "", includeStyles: Bool = true, includeHighlighting: Bool = false,
    style: DocumentStyle = .init(), includeMath: Bool = false
  ) -> String {
    let imageSources = remoteImages ? "mdasset: data: https:" : "mdasset: data:"
    return """
      <!doctype html><html><head><meta charset="utf-8">
      <title>\(escapeText(title))</title>
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src \(imageSources); style-src 'unsafe-inline' mdasset:; font-src mdasset: data:; script-src 'none'; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
      \(includeStyles ? "<style id=\"document-style\">" + style.css + "</style>" : "")\(includeHighlighting ? "<style id=\"code-style\">" + style.codeCSS + "</style>" : "")\(includeMath ? "<style id=\"math-style\">" + MathStyle.css + "</style>" : "")</head><body><main id="preview-content">\(body)</main></body></html>
      """
  }

  private static func escapeText(_ value: String) -> String {
    value.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&#39;")
  }

  /// Presentation updates never replace the document or its content nodes.
  public static let updateStyle = """
    const style = document.head.querySelector('#document-style');
    if (!style) return false;
    const anchor = [...document.querySelectorAll('#preview-content [data-sourcepos]')].find(e => e.getBoundingClientRect().bottom > 0);
    const anchorTop = anchor ? anchor.getBoundingClientRect().top : 0;
    style.textContent = css;
    const codeStyle = document.getElementById("code-style");
    if (codeStyle) codeStyle.textContent = codeCSS;
    if (anchor && anchor.isConnected) window.scrollBy(0, anchor.getBoundingClientRect().top - anchorTop);
    globalThis.__snowfolioScroll?.invalidateGeometry();
    globalThis.__snowfolioScroll?.markProgrammatic();
    return true;
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
    globalThis.__snowfolioScroll?.invalidateGeometry();
    globalThis.__snowfolioScroll?.markProgrammatic();
    return true;
    """
}
