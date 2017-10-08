//
//  RSSFeedParser.swift
//  RSSKit
//
//  Created by Quan Nguyen on 7/7/16.
//
//

import Foundation

public enum ConnectionType {
    case Asynchronously
    case Synchronously
}

public enum ParseType {
    case Full
    case ItemsOnly
    case InfoOnly
}

public enum FeedType {
    case Unknown
    case RSS
    case RSS1
    case Atom
}

//
@objc public protocol RSSFeedParserDelegate {
    @objc optional func feedParserDidStart(_ parser:RSSFeedParser)
    @objc optional func feedParser(_ parser:RSSFeedParser, didParseFeedInfo info:RSSFeedInfo)
    @objc optional func feedParser(_ parser:RSSFeedParser, didParseFeedItem item:RSSFeedItem)
    @objc optional func feedParserDidFinish(_ parser:RSSFeedParser)
    @objc optional func feedParser(_ parser:RSSFeedParser, didFailWithError error: NSError)
}

public class RSSFeedParser: NSObject {
    // Required
    public weak var delegate: RSSFeedParserDelegate?
    
    // Connection
    private var urlConnection : NSURLConnection?
    private var asyncData : Data?
    private var asyncTextEncodingName:String?
    public var connectionType: ConnectionType
    
    // Parsing
    public var feedParseType: ParseType
    private var feedParser : XMLParser?
    private var feedType: FeedType = .Unknown
    
    // Parsing Data
    private var currentPath: URL! = URL(string: "")
    private var currentText: String = ""
    private var currentElementAttributes:[String:String] = [:]
    private var item: RSSFeedItem?
    private var info: RSSFeedInfo?
    
    
    
    // Parsing State
    var aborted : Bool = false
    var parsing : Bool = false
    var stopped : Bool = true
    var failed : Bool = false
    var parsingComplete : Bool = false
    var hasEncounteredItems: Bool = false
    
    private var _url:URL?
    var url : URL? {
        get {
            return _url
        }
        
        set {
            guard let newVal = newValue else {
                return
            }
            _url = newVal
            
            if newVal.scheme == "feed" {
                let url = newVal as NSURL
                if url.resourceSpecifier != nil {
                _url = URL(string: String(format: "%@%@",
                    url.resourceSpecifier!.hasPrefix("//") == true ? "http:" : "",
                    url.resourceSpecifier!))
                }
            }
        }
    }
    
    // Parsing of XML structure as content
    private var pathOfElementWithXHTMLType : URL?
    private var parseStructureAsContent : Bool = false
    
    // Feed Downloading Properties
    private var request:URLRequest!
    
    
    private override init() {
        feedParseType = .Full
        connectionType = .Synchronously
        
        super.init()
    }
    
    public convenience init(feedURL : URL) {
        self.init()
        
        url = feedURL
        
        // Create default request with no caching
        
        var req = URLRequest(url: url!, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 60)
        
        req.setValue("KFeedParser", forHTTPHeaderField: "User-Agent")
        request = req
    }
    
    public convenience init(feedRequest:URLRequest) {
        self.init()
        url = feedRequest.url
        request = feedRequest
    }
    
    //MARK: - Parsing
    public func reset() {
        asyncData = nil
        asyncTextEncodingName = nil
        urlConnection = nil
        feedType = .Unknown
        currentPath = URL(string: "/")
        currentText = ""
        item = nil
        info = nil
        currentElementAttributes.removeAll()
        parseStructureAsContent = false
        pathOfElementWithXHTMLType = nil
        hasEncounteredItems = false
    }
    
    public func parse() -> Bool {
        // Reset
        reset()
        
        // Perform checks before parsing
        guard url != nil && delegate != nil else {
            parsingFailedWithError(RSSError.errorWithCode(.NotInitiated, failureReason: "Delegate or URL not specified"))
            return false
        }
        
        guard parsing == false else {
            parsingFailedWithError(RSSError.errorWithCode(.General, failureReason: "Cannot start parsing as parsing is already in progress"))
            return false
        }
        // Reset state for next parse
        parsing = true
        aborted = false
        stopped = false
        failed = false
        parsingComplete = false
        
        // Start
        var success = true
        
        //TODO: Debug log
        
        // Connection
        if connectionType == .Asynchronously {
            // Async
            urlConnection = NSURLConnection(request: request, delegate: self)
            if let _ = urlConnection {
                asyncData = Data()
            } else {
                parsingFailedWithError(RSSError.errorWithCode(.ConnectionFailed,
                    failureReason: "Asynchronous connection failed to URL: \(url!)"))
                success = false
            }
        } else {
            // Sync
            var response:URLResponse? = nil
            do  {
                let data = try NSURLConnection.sendSynchronousRequest(request,
                                                                      returning: &response)
                startParsingData(data, textEncodingName: response?.textEncodingName)
            } catch {
                parsingFailedWithError(RSSError.errorWithCode(.ConnectionFailed,
                    failureReason: "Synchronous connection failed to URL: \(url!)"))
                success = false
            }
        }
        
        // Cleanup & return
        return success
    }
    
    private func abortParsingEarly() {
        aborted = true
        feedParser?.abortParsing()
        parsingFinished()
    }
    
    public func stopParsing() {
        // Only if we're parsing
        guard parsing == true && parsingComplete == false else {
            return
        }
        
        // TODO: Debug log here
        
        // Stop
        stopped = true
        
        // Stop downloading
        urlConnection?.cancel()
        urlConnection = nil
        asyncData = nil
        asyncTextEncodingName = nil
        
        // Abort
        aborted = true
        feedParser?.abortParsing()
        
        // Finished
        parsingFinished()
    }
    
    private func parsingFinished() {
        if !parsingComplete {
            parsing = false
            parsingComplete = true
            delegate?.feedParserDidFinish?(self)
            reset()
        }
    }
    
    private func parsingFailedWithError(_ error:NSError) {
        
        if parsingComplete == false {
            // State
            failed = true
            parsing = false
            parsingComplete = true
            
            // TODO: log error here
            
            // Abort parsing
            if feedParser != nil {
                aborted = true
                feedParser?.abortParsing()
            }
            
            // Reset
            reset()
            
            // Inform delegate
            delegate?.feedParser?(self, didFailWithError: error)
        }
    }
    
    private func startParsingData(_ data1:Data?, textEncodingName:String?) {
        guard data1 != nil && feedParser == nil else {
            return
        }
        
        var data = data1
        
        // Create feed info
        let i = RSSFeedInfo()
        i.url = self.url
        self.info = i
        
        // Check whether it's UTF-8
        if textEncodingName?.lowercased() != "utf-8" {
            // Not UTF-8 so convert
            var string:String? = nil
            
            //TODO: Attempt to detect encoding from response header
            
            // If that failed then make our own attempts
            if string == nil {
                string = String(data: data!, encoding: String.Encoding.utf8)
            }
            
            if string == nil {
                string = String(data: data!, encoding: String.Encoding.isoLatin1)
            }
            
            if string == nil{
                string = String(data:data!, encoding:String.Encoding.macOSRoman)
            }
            
            // Nil data
            data = nil
            
            // Parse
            if let str = string {
                // Set XML encoding to UTF-8
                if str.hasPrefix("<?xml") {
                    if let range = str.range(of:"?>") {
                        let xmlDec = str[...range.lowerBound]
                        
                        if xmlDec.range(of:"encoding=\"UTF-8\"",
                                                options: .caseInsensitive,
                                                range: nil,
                                                locale: nil) == nil {
                            if let range2 = xmlDec.range(of:"encoding=\"") {
                                let subrange = range2.upperBound..<xmlDec.endIndex
                                if let range3 = xmlDec.range(of:"\"", options: .caseInsensitive, range: subrange, locale: nil) {
                                    let subrange2 = range2.lowerBound...range3.upperBound
                                    let temp = str.replacingCharacters(in: subrange2, with: "encoding=\"UTF-8\"")
                                    string = temp
                                }
                            }
                        }
                    }
                    
                }
                
                // Convert string to UTF-8 data
                if let str1 = string {
                    data = str1.data(using: String.Encoding.utf8)
                }
            }
        }
        
        // Create NSXMLParser
        if let data2 = data {
            let newFeedParser = XMLParser(data: data2)
            self.feedParser = newFeedParser
            // Parse
            if feedParser != nil {
                feedParser?.delegate = self
                feedParser?.shouldProcessNamespaces = true
                feedParser?.parse()
                feedParser = nil // Release after parse
            } else {
                parsingFailedWithError(RSSError.errorWithCode(.FeedParsingError, failureReason: "Feed not a valid XML"))
            }
        } else {
            parsingFailedWithError(RSSError.errorWithCode(.FeedParsingError, failureReason: "Errorwith feed encoding"))
        }
    }
    
    
    
    // MARK: - Send Items to delegate
    private func dispatchFeedInfoToDelegate() {
        guard let feedInfo = info else {return}
        
        delegate?.feedParser?(self, didParseFeedInfo: feedInfo)
        
        info = nil
    }
    
    private func dispatchFeedItemToDelegate() {
        guard let feedItem = item else {return}
        
        // Process before hand
        if item?.summary == nil {
            item?.summary = item?.content
            item?.content = nil
        }
        
        if item?.date == nil && item?.updated != nil {
            item?.date = item?.updated
        }
        
        // Inform delegate
        delegate?.feedParser?(self, didParseFeedItem: feedItem)
        
        // Finish
        item = nil
    }
    
    // MARK: - Helper functions
    private func isElementEmpty(elementName:String) -> Bool {
        let tags = ["br", "img", "input", "hr", "link", "base", "basefont", "frame", "meta", "area", "col", "param"]
        return tags.filter{$0 == elementName}.count > 0 ? true : false
    }
    
    @discardableResult private func createEnclosureFromAttributes(_ attributes:[String:String], andAddToItem currentItem:RSSFeedItem) -> Bool {
        // Create enclosure
        var enclosure:[String:Any]? = nil
        var encURL:String? = nil
        var encType:String? = nil
        var encLength:Int? = nil
        
        switch feedType {
        case .RSS:
            encURL = attributes["url"]
            encType = attributes["type"]
            if let length = attributes["length"] {
                encLength = Int(length)
            }
            break
        case .RSS1:
            encURL = attributes["rdf:resource"]
            encType = attributes["enc:type"]
            if let length = attributes["enc:length"] {
                encLength = Int(length)
            }
            break
        case .Atom:
            if attributes["rel"] == "enclosure" {
                encURL = attributes["href"]
                encType = attributes["type"]
                if let length = attributes["length"] {
                    encLength = Int(length)
                }
            }
            break
        default:
            break
        }
        
        if encURL != nil {
            enclosure = ["url" : encURL!]
            if let encType = encType {
                enclosure!["type"] = encType
            }
            
            if let encLength = encLength {
                enclosure!["length"] = encLength
            }
        }
        
        // Add to item
        if let enclosure = enclosure {
            if currentItem.enclosures != nil {
                currentItem.enclosures?.append(enclosure)
            } else {
                currentItem.enclosures = [enclosure]
            }
            
            return true
        } else {
            return false
        }
    }
    
    // Process ATOM link and determine whether to ignore it, add it as the link element or add as enclosure
    // Links can be added to item
    @discardableResult private func processAtomLink(attributes:[String:String], andAddToItem item:RSSFeedItem) -> Bool {
        if let rel = attributes["rel"] {
            // Use as link if rel == alternate
            if rel == "alternate" {
                item.link = attributes["href"]
                return true
            }
            
            if rel == "enclosure" {
                createEnclosureFromAttributes(attributes, andAddToItem: item)
                return true
            }
        }
        
        return false
    }
    
    @discardableResult private func processAtomLink(attributes:[String:String], andAddToInfo info:RSSFeedInfo) -> Bool {
        if let rel = attributes["rel"] {
            // Use as link if rel == alternate
            if rel == "alternate" {
                info.link = attributes["href"]
                return true
            }
        }
        
        return false
    }
}

extension RSSFeedParser : NSURLConnectionDataDelegate {
    public func connection(_ connection:NSURLConnection, didReceive response:URLResponse) {
        self.asyncData?.count = 0
        self.asyncTextEncodingName = response.textEncodingName
    }
    
    public func connection(_ connection:NSURLConnection, didReceive data:Data) {
        self.asyncData?.append(data)
    }
    
    public func connection(_ connection: NSURLConnection, didFailWithError error: Error) {
        // Failed
        self.urlConnection = nil
        self.asyncData = nil
        self.asyncTextEncodingName = nil
        
        // Error
        self.parsingFailedWithError(RSSError.errorWithCode(.ConnectionFailed, failureReason: "\(error.localizedDescription)"))
    }
    
    public func connectionDidFinishLoading(_ connection: NSURLConnection) {
        // Succeed
        
        // Parse
        if self.stopped == false {
            self.startParsingData(self.asyncData, textEncodingName: self.asyncTextEncodingName)
        }
        
        // Cleanup
        self.urlConnection = nil
        self.asyncData = nil
        self.asyncTextEncodingName = nil
    }
    
    public func connection(_ connection: NSURLConnection, willCacheResponse cachedResponse: CachedURLResponse) -> CachedURLResponse? {
        return nil // Don't cache
    }
}

extension RSSFeedParser : XMLParserDelegate {
    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String]) {
        
        // Adjust path
        currentPath = currentPath.appendingPathComponent(qName!)
        currentElementAttributes = attributeDict
        
        // Parse content as structure
        // - Use elementName not qualifiedName to ignore XML namespaces for XHTML entities
        if parseStructureAsContent {
            // Open XHTML tag
            currentText.append("<\(elementName)")
            
            // Add attributes
            for kv in attributeDict {
                let value = kv.1.stringByEncodingHTMLEntities()
                currentText.append(" \(kv.0)=\"\(value)\"")
            }
            
            // End tag or close
            if isElementEmpty(elementName: elementName) {
                currentText.append(" />")
            } else {
                currentText.append(">")
            }
            
            // Dont continue
            return
        }
        
        // Reset
        currentText = ""
        
        // Determine feed type
        if feedType == .Unknown {
            if qName == "rss" {
                feedType = .RSS
            } else if qName == "rdf:RDF" {
                feedType = .RSS1
            } else if qName == "feed" {
                feedType = .Atom
            } else {
                self.parsingFailedWithError(RSSError.errorWithCode(.FeedParsingError, failureReason: "XML document is not a valid web feed document."))
            }
            
            return
        }
        
        // Entering new feed element
        if feedParseType != .ItemsOnly {
            if feedType == .RSS && currentPath.absoluteString == "/rss/channel" ||
                feedType == .RSS1 && currentPath.absoluteString == "/rdf:RDF/channel" ||
                feedType == .Atom && currentPath.absoluteString == "/feed" {
                return
            }
        }
        
        // Entering new item element
        if feedType == .RSS && currentPath.absoluteString == "/rss/channel/item" ||
            feedType == .RSS1 && currentPath.absoluteString == "/rdf:RDF/item" ||
            feedType == .Atom && currentPath.absoluteString == "/feed/entry" {
            
            // Send off feed info to delegate
            if !hasEncounteredItems {
                hasEncounteredItems = true
                if feedParseType != .ItemsOnly {
                    // Dispatch feed info to delegate
                    self.dispatchFeedInfoToDelegate()
                    
                    if feedParseType == .InfoOnly {
                        // Finish
                        self.abortParsingEarly()
                        return
                    }
                } else {
                    // Ignoring feed info
                }
            }
            
            // New item
            self.item = RSSFeedItem()
            
            return
        }
        
        // Check if entering into an Atom content tag with type "xhtml"
        // If type is "xhtml" then it can contain child elements and structure needs
        // to be parsed as content
        // See: http://www.atomenabled.org/developers/syndication/atom-format-spec.php#rfc.section.3.1.1
        if feedType == .Atom {
            let typeAttribute = attributeDict["type"]
            
            if typeAttribute == "xhtml" {
                // Start parsing structure as content
                parseStructureAsContent = true
                
                // Remember path so we can stop parsing structure when element ends
                pathOfElementWithXHTMLType = currentPath
            }
        }
    }
    
    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        //
        if parseStructureAsContent {
            // Check for finishing parsing structure as content
            if currentPath.absoluteString.characters.count > pathOfElementWithXHTMLType?.absoluteString.characters.count ?? 0 {
                // Close XHTML tag unless it is an empty element
                if !isElementEmpty(elementName: elementName) {
                    currentText.append("</\(elementName)>")
                }
                
                // Adjust path & don't continue
                
                
                self.currentPath = self.currentPath.deletingLastPathComponent()
                
                return
            }
            
            // Finish
            parseStructureAsContent = false
            self.pathOfElementWithXHTMLType = nil
            
            // Continue...
        }
        
        // Store data
        var processed = false
        
        // Remove newlines and whitespace from currentText
        let processedText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Process
        switch feedType {
        case .RSS:
            // Item
            if !processed {
                if currentPath.absoluteString == "/rss/channel/item/title" {
                    if processedText.characters.count > 0 {
                        item?.title = processedText
                        processed = true
                    }
                } else if currentPath.absoluteString == "/rss/channel/item/link" {
                    if processedText.characters.count > 0 {
                        item?.link = processedText
                        processed = true
                    }
                } else if currentPath.absoluteString == "/rss/channel/item/author" {
                    if processedText.characters.count > 0 {
                        item?.author = processedText
                        processed = true
                    }
                } else if currentPath.absoluteString == "/rss/channel/item/dc:creator" {
                    if processedText.characters.count > 0 {
                        item?.author = processedText
                        processed = true
                    }
                } else if currentPath.absoluteString == "/rss/channel/item/guid" {
                    if processedText.characters.count > 0 {
                        item?.identifier = processedText
                        processed = true
                    }
                } else if currentPath.absoluteString == "/rss/channel/item/description" {
                    if processedText.characters.count > 0 {
                        item?.summary = processedText
                        processed = true
                    }
                } else if currentPath.absoluteString == "/rss/channel/item/content:encoded" {
                    if processedText.characters.count > 0 {
                        item?.content = processedText
                        processed = true
                    }
                } else if currentPath.absoluteString == "/rss/channel/item/pubDate" {
                    if processedText.characters.count > 0 {
                        item?.date = Date.dateFromInternetDateTimeString(processedText, formatHint: DateFormatHint.RFC822)
                        processed = true
                    }
                } else if currentPath.absoluteString == "/rss/channel/item/enclosure" {
                    createEnclosureFromAttributes(currentElementAttributes, andAddToItem: item!)
                    processed = true
                } else if currentPath.absoluteString == "/rss/channel/item/dc:date" {
                    if processedText.characters.count > 0 {
                        item!.date = Date.dateFromInternetDateTimeString(processedText, formatHint: .RFC3339)
                        processed = true
                    }
                }
            }
            
            // Info
            if !processed && feedParseType != .ItemsOnly {
                if currentPath.absoluteString == "/rss/channel/title" {
                    if processedText.characters.count > 0 {
                        info?.title = processedText
                        processed = true
                    }
                } else if currentPath.absoluteString == "/rss/channel/description" {
                    if processedText.characters.count > 0 {
                        info?.summary = processedText
                        processed = true
                    }
                } else if currentPath.absoluteString == "/rss/channel/link" {
                    if processedText.characters.count > 0 {
                        info?.link = processedText
                        processed = true
                    }
                }
            }
            break
        case .RSS1:
            // Item
            if !processed {
                if currentPath.absoluteString == "/rdf:RDF/item/title" {
                    if processedText.characters.count > 0 {
                        item?.title = processedText
                        processed = true
                    }
                } else if currentPath.absoluteString == "/rdf:RDF/item/link" {
                    if processedText.characters.count > 0 {
                        item?.link = processedText
                        processed = true
                    }
                } else if currentPath.absoluteString == "/rdf:RDF/item/description" {
                    if processedText.characters.count > 0 {
                        item?.summary = processedText
                        processed = true
                    }
                } else if currentPath.absoluteString == "/rdf:RDF/item/content:encoded" {
                    if processedText.characters.count > 0 {
                        item?.content = processedText
                        processed = true
                    }
                } else if currentPath.absoluteString == "/rdf:RDF/item/dc:identifier" {
                    if processedText.characters.count > 0 {
                        item?.identifier = processedText
                        processed = true
                    }
                } else if currentPath.absoluteString == "/rdf:RDF/item/dc:creator" {
                    if processedText.characters.count > 0 {
                        item?.author = processedText
                        processed = true
                    }
                } else if currentPath.absoluteString == "/rdf:RDF/item/dc:date" {
                    if processedText.characters.count > 0 {
                        item?.date = Date.dateFromInternetDateTimeString(processedText, formatHint: .RFC3339)
                        processed = true
                    }
                } else if currentPath.absoluteString == "/rdf:RDF/item/enc:enclosure" {
                    createEnclosureFromAttributes(currentElementAttributes, andAddToItem: item!)
                    processed = true
                }
            }
            
            // Info
            if !processed && feedParseType != .ItemsOnly {
                if currentPath.absoluteString == "/rdf:RDF/channel/title" {
                    if processedText.characters.count > 0 {
                        info?.title = processedText
                        processed = true
                    }
                } else if currentPath.absoluteString == "/rdf:RDF/channel/description" {
                    if processedText.characters.count > 0 {
                        info?.summary = processedText
                        processed = true
                    }
                } else if currentPath.absoluteString == "/rdf:RDF/channel/link" {
                    if processedText.characters.count > 0 {
                        info?.link = processedText
                        processed = true
                    }
                }
            }
            break
        case .Atom:
            // Item
            if !processed {
                if currentPath.absoluteString == "/feed/entry/title" {
                    if processedText.characters.count > 0 {
                        item?.title = processedText
                        processed = true
                    }
                } else if currentPath.absoluteString == "/feed/entry/link" {
                    processAtomLink(attributes:currentElementAttributes, andAddToItem: item!)
                    processed = true
                } else if currentPath.absoluteString == "/feed/entry/id" {
                    if processedText.characters.count > 0 {
                        item?.identifier = processedText
                        processed = true
                    }
                } else if currentPath.absoluteString == "/feed/entry/summary" {
                    if processedText.characters.count > 0 {
                        item?.summary = processedText
                        processed = true
                    }
                } else if currentPath.absoluteString == "/feed/entry/content" {
                    if processedText.characters.count > 0 {
                        item?.content = processedText
                        processed = true
                    }
                } else if currentPath.absoluteString == "/feed/entry/author/name" {
                    if processedText.characters.count > 0 {
                        item?.author = processedText
                        processed = true
                    }
                } else if currentPath.absoluteString == "/feed/entry/dc:creator" {
                    if processedText.characters.count > 0 {
                        item?.author = processedText
                        processed = true
                    }
                } else if currentPath.absoluteString == "/feed/entry/published" {
                    if processedText.characters.count > 0 {
                        item?.date = Date.dateFromInternetDateTimeString(processedText, formatHint: .RFC3339)
                        processed = true
                    }
                } else if currentPath.absoluteString == "/feed/entry/updated" {
                    if processedText.characters.count > 0 {
                        item?.updated = Date.dateFromInternetDateTimeString(processedText, formatHint: .RFC3339)
                        processed = true
                    }
                }
            }
            
            // Info
            if !processed && feedParseType != .ItemsOnly {
                if currentPath.path == "/feed/title" {
                    if processedText.characters.count > 0 {
                        info?.title = processedText
                        processed = true
                    }
                } else if currentPath.path == "/feed/description" {
                    if processedText.characters.count > 0 {
                        info?.summary = processedText
                        processed = true
                    }
                } else if currentPath.path == "/feed/link" {
                    processAtomLink(attributes:currentElementAttributes, andAddToInfo: info!)
                    processed = true
                }
            }
            
            break
        default:
            break
        }
        
        // Adjust path
        currentPath = currentPath.deletingLastPathComponent()
        
        // If end of an item then tell delegate
        if !processed {
            if ((feedType == .RSS || feedType == .RSS1) && qName == "item") ||
                (feedType == .Atom && qName == "entry") {
                dispatchFeedItemToDelegate()
            }
        }
        
        // Check if the document has finished parsing and send off info if needed (i.e. there were no items)
        if !processed {
            if feedType == .RSS && qName == "rss" ||
                feedType == .RSS1 && qName == "rdf:RDF" ||
                feedType == .Atom && qName == "feed" {
                if info != nil && feedParseType != .ItemsOnly {
                    dispatchFeedInfoToDelegate()
                }
            }
        }
    }
    
    public func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        // Remember characters
        var str:String? = nil
        
        // Try decoding with NSUTF8StringEncoding & NSISOLatin1StringEncoding
        str = String(data: CDATABlock, encoding: String.Encoding.utf8)
        if str == nil {
            str = String(data: CDATABlock, encoding: String.Encoding.isoLatin1)
        }
        
        if str != nil {
            currentText.append(str!)
        }
    }
    
    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        // Remember characters
        if !parseStructureAsContent {
            // Add characters normally
            currentText.append(string)
        } else {
            // If parsing structure as content then we should encode characters
            currentText.append(string.stringByEncodingHTMLEntities())
        }
    }
    
    public func parserDidStartDocument(_ parser: XMLParser) {
        self.delegate?.feedParserDidStart?(self)
    }
    
    public func parserDidEndDocument(_ parser: XMLParser) {
        self.parsingFinished()
    }
    
    public func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if !aborted {
            parsingFailedWithError(RSSError.errorWithCode(.FeedParsingError, failureReason: parseError.localizedDescription))
        }
    }
    
    public func parser(_ parser: XMLParser, validationErrorOccurred validationError: Error) {
        parsingFailedWithError(RSSError.errorWithCode(.FeedValidationError, failureReason: validationError.localizedDescription))
    }
}
