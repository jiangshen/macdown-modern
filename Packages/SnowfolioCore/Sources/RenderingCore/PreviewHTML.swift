import Foundation
import MathCore

public enum PreviewHTML {
  public static func document(
    body: String = "", remoteImages: Bool = false,
    title: String = "", includeStyles: Bool = true, includeHighlighting: Bool = false,
    style: DocumentStyle = .init(), includeMath: Bool = false
  ) -> String {
    let parts = HTMLDocumentParts(
      body: body, title: title, style: style,
      includeStyles: includeStyles, includeHighlighting: includeHighlighting,
      includeMath: includeMath, remoteImages: remoteImages)
    return """
      <!doctype html><html><head><meta charset="utf-8">
      \(parts.titleTag)
      <meta name="viewport" content="width=device-width, initial-scale=1">
      \(parts.policy)
      \(parts.styleTags.joined())</head><body\(parts.bodyAttributes)>\(parts.body)</body></html>
      """
  }

  /// Presentation updates never replace the document or its content nodes.
  public static let updateStyle = """
    const style = document.head.querySelector('#document-style');
    if (!style) return false;
    const anchor = [...document.querySelectorAll('#preview-content [data-sourcepos]')].find(e => e.getBoundingClientRect().bottom > 0);
    const anchorTop = anchor ? anchor.getBoundingClientRect().top : 0;
    const root = document.getElementById('preview-content');
    if (!root) return false;
    const wantsBody = typeof bodyRoot === 'boolean' ? bodyRoot : root === document.body;
    const changingRoot = wantsBody !== (root === document.body);
    const selection = window.getSelection();
    function boundary(node, offset) {
      if (node === root) return {container: true, offset};
      if (node === document.body && root.parentNode === node && node.childNodes.length === 1)
        return {container: true, offset: offset === 0 ? 0 : root.childNodes.length};
      return {node, offset};
    }
    const selected = changingRoot && selection && selection.rangeCount ? {
      anchor: boundary(selection.anchorNode, selection.anchorOffset),
      focus: boundary(selection.focusNode, selection.focusOffset)
    } : null;
    if (wantsBody && root !== document.body) {
      while (root.firstChild) document.body.insertBefore(root.firstChild, root);
      root.remove(); document.body.id = 'preview-content';
    } else if (!wantsBody && root === document.body) {
      document.body.removeAttribute('id');
      const main = document.createElement('main'); main.id = 'preview-content';
      while (document.body.firstChild) main.appendChild(document.body.firstChild);
      document.body.appendChild(main);
    }
    style.textContent = css;
    const nextRoot = document.getElementById('preview-content');
    const endpoint = point => point.container
      ? {node: nextRoot, offset: Math.min(point.offset, nextRoot.childNodes.length)} : point;
    if (selected) {
      const a = endpoint(selected.anchor), f = endpoint(selected.focus);
      if (a.node?.isConnected && f.node?.isConnected)
        selection.setBaseAndExtent(a.node, a.offset, f.node, f.offset);
    }
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
    const selection = window.getSelection();
    const codeFor = node => (node?.nodeType === Node.ELEMENT_NODE ? node : node?.parentElement)?.closest('pre > code');
    const selectedCode = selection?.rangeCount === 1 ? codeFor(selection.anchorNode) : null;
    const codeOffset = (node, offset) => {
      const range = document.createRange(); range.selectNodeContents(selectedCode); range.setEnd(node, offset);
      return range.toString().length;
    };
    const codeSelection = selectedCode && root.contains(selectedCode) && codeFor(selection.focusNode) === selectedCode ? {
      position: selectedCode.parentElement.getAttribute('data-sourcepos'), text: selectedCode.textContent,
      anchor: codeOffset(selection.anchorNode, selection.anchorOffset), focus: codeOffset(selection.focusNode, selection.focusOffset),
      pre: selectedCode.parentElement
    } : null;
    function sync(oldParent, newParent) {
      const next = [...newParent.childNodes];
      for (let index = 0; index < next.length; index++) {
        const wanted = next[index], existing = oldParent.childNodes[index];
        if (!existing) { oldParent.appendChild(wanted.cloneNode(true)); continue; }
        if (wanted.nodeType===Node.ELEMENT_NODE && wanted.matches('div.md-diagram[data-diagram-key]')) {
          if (existing.nodeType===Node.ELEMENT_NODE && existing.matches('div.md-diagram[data-diagram-key]') &&
            existing.getAttribute('data-diagram-key')===wanted.getAttribute('data-diagram-key')) {
            for (const attr of [...existing.attributes]) if (!wanted.hasAttribute(attr.name)) existing.removeAttribute(attr.name);
            for (const attr of [...wanted.attributes]) existing.setAttribute(attr.name,attr.value);
          } else {oldParent.replaceChild(wanted.cloneNode(true),existing);}
          continue;
        }
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
    let restoredCode;
    if (codeSelection?.position) {
      restoredCode = [...root.querySelectorAll('pre[data-sourcepos] > code')].find(code =>
        code.parentElement.getAttribute('data-sourcepos') === codeSelection.position && code.textContent === codeSelection.text);
      if (restoredCode) {
        const endpoint = offset => {
          const walker = document.createTreeWalker(restoredCode, NodeFilter.SHOW_TEXT);
          let node; while (node = walker.nextNode()) {
            if (offset <= node.length) return {node, offset}; offset -= node.length;
          }
          return {node: restoredCode, offset: restoredCode.childNodes.length};
        };
        const a = endpoint(codeSelection.anchor), f = endpoint(codeSelection.focus);
        selection.setBaseAndExtent(a.node, a.offset, f.node, f.offset);
      }
    }
    for (const figure of root.querySelectorAll('div.md-diagram[data-diagram-key]')) {
      const template=figure.querySelector(':scope > template[data-snowfolio-diagram]');
      if (!template) continue;
      const shadow=figure.shadowRoot ?? figure.attachShadow({mode:'open'});
      shadow.replaceChildren(template.content.cloneNode(true)); template.remove();
    }
    if (anchor && anchor.isConnected) window.scrollBy(0, anchor.getBoundingClientRect().top - anchorTop);
    else if (restoredCode && anchor === codeSelection.pre) window.scrollBy(0, restoredCode.parentElement.getBoundingClientRect().top - anchorTop);
    else window.scrollTo(0, previousY);
    globalThis.__snowfolioScroll?.invalidateGeometry();
    globalThis.__snowfolioScroll?.markProgrammatic();
    return true;
    """
}
