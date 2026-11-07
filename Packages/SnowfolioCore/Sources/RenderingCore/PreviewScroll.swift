import Foundation

/// Installed only by the native preview in WKContentWorld.defaultClient. This is
/// never embedded in documents or exports, and page JavaScript remains disabled.
public enum PreviewScroll {
  public static let bootstrap = """
    (() => {
      if (globalThis.__snowfolioScroll) return;
      let inputEpoch = 0;
      let token = '', revision = '', targetY = null, frame = 0, ended = 0, geometry = null, retainedPosition = null;
      function blocks() {
        if (geometry) return geometry;
        geometry = [...document.querySelectorAll('#preview-content [data-sourcepos]')].flatMap(element => {
          const match = /^(\\d+):\\d+-(\\d+):\\d+$/.exec(element.getAttribute('data-sourcepos') ?? '');
          if (!match) return [];
          const start = Number(match[1]), end = Number(match[2]) + 1;
          const rect = element.getBoundingClientRect();
          if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start < 1 || end <= start || rect.height <= 0) return [];
          return [{start, end, y: rect.top + window.scrollY, height: rect.height}];
        });
        return geometry;
      }
      function position() {
        const values = blocks(), y = window.scrollY;
        const covering = values.filter(b => b.y <= y + .5 && b.y + b.height > y + .5)
          .sort((a,b) => a.height - b.height || (a.end-a.start) - (b.end-b.start));
        const next = covering[0] ?? values.filter(b => b.y >= y).sort((a,b) => a.y-b.y)[0];
        const last = values.sort((a,b) => b.y-a.y)[0];
        const block = next ?? last;
        const fraction = block ? Math.max(0, Math.min(1, (y-block.y)/block.height)) : 0;
        const line = block ? block.start + fraction*(block.end-block.start) : 1;
        const maximum = Math.max(0, document.documentElement.scrollHeight-window.innerHeight);
        return {line, atTop:y <= .5, atBottom:maximum > .5 && y >= maximum-.5};
      }
      function report(settled) {
        if (!token || !revision) return;
        const programmatic = targetY !== null && Math.abs(window.scrollY-targetY) < 2;
        if (settled) targetY = null;
        window.webkit.messageHandlers.snowfolioScroll.postMessage({token, revision, position:position(), programmatic, settled});
      }
      function markProgrammatic() { targetY = window.scrollY; }
      function scrollToPosition(line, atTop, atBottom) {
        if (!Number.isFinite(line) || line < 1) return false;
        const values = blocks();
        const covering = values.filter(b => b.start <= line && line < b.end)
          .sort((a,b) => (a.end-a.start)-(b.end-b.start) || a.height-b.height);
        let y = 0;
        if (covering.length) {
          const block = covering[0];
          y = block.y + (line-block.start)/(block.end-block.start)*block.height;
        } else {
          const before = values.filter(b => b.end <= line).sort((a,b) => b.end-a.end || b.y-a.y)[0];
          const after = values.filter(b => b.start > line).sort((a,b) => a.start-b.start || a.y-b.y)[0];
          if (before && after) {
            const fraction = (line-before.end)/Math.max(1, after.start-before.end);
            y = before.y + before.height + fraction*(after.y-before.y-before.height);
          } else if (before) y = before.y+before.height;
          else if (after) y = after.y;
        }
        const maximum = Math.max(0, document.documentElement.scrollHeight-window.innerHeight);
        if (atTop) y=0; else if (atBottom) y=maximum;
        window.scrollTo({left:0, top:Math.max(0,Math.min(maximum,y)), behavior:'instant'});
        retainedPosition = {line, atTop, atBottom};
        markProgrammatic();
        return true;
      }
      for (const type of ['wheel','pointerdown','touchstart','keydown']) {
        window.addEventListener(type, () => {inputEpoch++; retainedPosition=null; targetY=null;}, {passive:true,capture:true});
      }
      window.addEventListener('scroll', () => {
        if (targetY === null || Math.abs(window.scrollY-targetY) >= 2) retainedPosition=null;
        if (!frame) frame=requestAnimationFrame(() => {frame=0; report(false);});
        clearTimeout(ended); ended=setTimeout(() => report(true),120);
      }, {passive:true});
      // The body persists when reading styles add or remove the main wrapper.
      const root = document.body;
      if (root) new ResizeObserver(() => {
        geometry=null;
        if (retainedPosition) scrollToPosition(retainedPosition.line,retainedPosition.atTop,retainedPosition.atBottom);
      }).observe(root);
      window.addEventListener('resize', () => {geometry=null;}, {passive:true});
      globalThis.__snowfolioScroll = {
        invalidateGeometry() {geometry=null;},
        activate(nextToken,nextRevision) {if (revision!==nextRevision || token!==nextToken) retainedPosition=null; token=nextToken; revision=nextRevision; geometry=null; markProgrammatic();},
        get inputEpoch() {return inputEpoch;},
        position, scrollToPosition, markProgrammatic
      };
    })();
    """

  public static let activate = """
    const state = globalThis.__snowfolioScroll;
    if (!state) return false;
    state.activate(token, revision);
    return true;
    """

  public static let move = """
    return globalThis.__snowfolioScroll?.scrollToPosition(line, atTop, atBottom) ?? false;
    """
}
