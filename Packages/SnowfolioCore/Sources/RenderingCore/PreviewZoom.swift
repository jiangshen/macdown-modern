import Foundation

/// Trusted client-world helpers; zoom never enters document or export HTML.
public enum PreviewZoom {
  public static let capture = """
    const maximum = Math.max(0, document.documentElement.scrollHeight-window.innerHeight);
    return {
      position:globalThis.__snowfolioScroll?.position() ?? null,
      inputEpoch:globalThis.__snowfolioScroll?.inputEpoch ?? null,
      fraction:maximum > 0 ? Math.max(0,Math.min(1,window.scrollY/maximum)) : 0
    };
    """

  public static let restore = """
    // WebKit publishes the new CSS viewport after the native pageZoom change.
    await new Promise(resolve => {
      // Background tabs and a locked desktop can pause animation frames.
      const timer = setTimeout(resolve, 100);
      requestAnimationFrame(() => requestAnimationFrame(() => {clearTimeout(timer); resolve();}));
    });
    const state = globalThis.__snowfolioScroll;
    // New input supersedes a reading anchor captured before the zoom began.
    if (inputEpoch === null || state?.inputEpoch === inputEpoch) {
      state?.invalidateGeometry();
      if (!(line !== null && state?.scrollToPosition(line, atTop, atBottom))) {
        const maximum = Math.max(0, document.documentElement.scrollHeight-window.innerHeight);
        window.scrollTo({left:0,top:maximum*fraction,behavior:'instant'});
        state?.markProgrammatic();
      }
    }
    """ + "\n" + capture
}
