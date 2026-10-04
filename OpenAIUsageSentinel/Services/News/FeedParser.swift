import Foundation

public struct FeedItem: Sendable { var title = ""; var url = ""; var content = ""; var date: Date?; var author: String? }
public final class FeedParser: NSObject, XMLParserDelegate {
    private var items: [FeedItem] = []
    private var current: FeedItem?
    private var text = ""
    private var stack: [String] = []
    public static func parse(_ data: Data) throws -> [FeedItem] {
        let delegate = FeedParser(), parser = XMLParser(data: data)
        parser.delegate = delegate; parser.shouldResolveExternalEntities = false
        guard parser.parse() else { throw SentinelError.unavailable("Malformed RSS/Atom feed.") }
        return delegate.items
    }
    public func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        stack.append(name); text = ""
        if name == "entry" || name == "item" { current = FeedItem() }
        if name == "link", let href = attributes["href"], attributes["rel"] == nil || attributes["rel"] == "alternate" { current?.url = href }
    }
    public func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    public func parser(_ parser: XMLParser, foundCDATA data: Data) { text += String(data: data, encoding: .utf8) ?? "" }
    public func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if current != nil {
            switch name {
            case "title": current?.title = value
            case "link": if !value.isEmpty { current?.url = value }
            case "content", "description", "summary", "content:encoded": if value.count > (current?.content.count ?? 0) { current?.content = value }
            case "published", "pubDate": current?.date = DateParsing.parse(value)
            case "updated": if current?.date == nil { current?.date = DateParsing.parse(value) }
            case "name": if stack.contains("author") { current?.author = value }
            case "author", "dc:creator": if current?.author == nil && !value.isEmpty { current?.author = value }
            case "entry", "item": if let item = current { items.append(item) }; current = nil
            default: break
            }
        }
        _ = stack.popLast(); text = ""
    }
    public static func plainText(_ html: String) -> String {
        html.replacingOccurrences(of: "(?is)<(script|style)[^>]*>.*?</\\1>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
