import Foundation
import JavaScriptCore

/// Confined to the reading-style repository actor. The pinned parser has no DOM,
/// native, file or network bindings; authored CSS is passed as data, never code.
final class CSSResourceParser {
  struct Reference: Decodable {
    let start: Int
    let end: Int
    let value: String
    let string: Bool
    let role: String
  }
  private var context: JSContext?

  func references(in css: String) throws -> [Reference] {
    try Task.checkCancellation()
    if context == nil {
      guard
        let url = Bundle.module.url(
          forResource: "CSSParser", withExtension: "js", subdirectory: "CSS"),
        let engine = JSContext()
      else { throw StyleAssetFailure.parserUnavailable }
      engine.evaluateScript(try String(contentsOf: url, encoding: .utf8))
      engine.evaluateScript(Self.bridge)
      guard engine.exception == nil else { throw StyleAssetFailure.parserUnavailable }
      context = engine
    }
    guard let context else { throw StyleAssetFailure.parserUnavailable }
    context.exception = nil
    let value = context.objectForKeyedSubscript("snowfolioCSSReferences")?.call(withArguments: [css]
    )
    guard context.exception == nil, let json = value?.toString(),
      let data = json.data(using: .utf8)
    else {
      let reason = context.exception?.toString() ?? ""
      context.exception = nil
      if reason.contains("limit") || reason.hasPrefix("RangeError") {
        throw StyleAssetFailure.tooComplex
      }
      throw StyleAssetFailure.unsupportedSyntax
    }
    let references = try JSONDecoder().decode([Reference].self, from: data)
    try Task.checkCancellation()
    return references
  }

  private static let bridge = """
    function snowfolioCSSReferences(css) {
      const ast=SnowfolioCSS.parse(css,{positions:true,parseCustomProperty:true,
        onParseError(){throw new Error('Unsupported CSS syntax');}});
      const references=[], stack=[];
      let count=0;
      const name=n=>SnowfolioCSS.ident.decode(n.name??'').toLowerCase();
      SnowfolioCSS.walk(ast,{
        enter(node) {
          if (++count>100000 || stack.length>128) throw new Error('CSS complexity limit');
          const parent=stack[stack.length-1];
          if (node.type==='Raw') throw new Error('Unparsed CSS');
          const namespace=stack.some(n=>n.type==='Atrule' && name(n)==='namespace');
          const importing=stack.some(n=>n.type==='Atrule' && name(n)==='import');
          const importDestination=importing && parent?.type==='AtrulePrelude' && parent.children.first===node;
          const fetching=importDestination || !importing && !stack.some(n=>n.type==='AtrulePrelude') &&
            stack.some(n=>n.type==='Declaration');
          const font=stack.some(n=>n.type==='Atrule' && name(n)==='font-face') &&
            stack.some(n=>n.type==='Declaration' && SnowfolioCSS.ident.decode(n.property).toLowerCase()==='src');
          const imageFunction=parent?.type==='Function' &&
            ['image-set','-webkit-image-set','image','src'].includes(name(parent));
          const importString=importDestination;
          if (!namespace && fetching && (node.type==='Url' || node.type==='String' && (imageFunction || importString))) {
            if (references.length>=2048) throw new Error('CSS resource limit');
            references.push({start:node.loc.start.offset,end:node.loc.end.offset,
              value:node.value,string:node.type==='String',role:importing?'import':font?'font':'image'});
          }
          stack.push(node);
        },
        leave(){stack.pop();}
      });
      return JSON.stringify(references);
    }
    """
}
