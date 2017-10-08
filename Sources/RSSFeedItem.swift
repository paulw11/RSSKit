//
//  RSSFeedItem.swift
//  RSSKit
//
//  Created by Quan Nguyen on 7/7/16.
//
//

import Foundation

public class RSSFeedItem: NSObject {
    public var identifier:String?
    public var title:String?
    public var link:String?
    public var date:Date?        // Date the item was published
    public var updated:Date?     // Date the item was updated if available
    public var summary:String?
    public var content:String?
    public var author:String?
    
    // Enclosures: Holds 1 ore more item enclosures (i.e. podcasts, mp3. pdf, etc)
    // - Array of dictionaries with the following keys:
    //      url: where the enclosure is located (String)
    //      length: how big it is in bytes (Int)
    //      type: what its type is, a standard MIME type (String)
    public var enclosures:[Any]?
    
    public var otherTags:[String:String]?
    
    public override init() {
        super.init()
    }
    
    required public init(coder aDecoder: NSCoder) {
        identifier = aDecoder.decodeObject(forKey: "identifier") as? String
        title = aDecoder.decodeObject(forKey: "title") as? String
        link = aDecoder.decodeObject(forKey: "link") as? String
        date = aDecoder.decodeObject(forKey: "date") as? Date
        updated = aDecoder.decodeObject(forKey: "updated") as? Date
        summary = aDecoder.decodeObject(forKey: "summary") as? String
        content = aDecoder.decodeObject(forKey: "content") as? String
        author = aDecoder.decodeObject(forKey: "author") as? String
    }
    
    public func encode(with aCoder: NSCoder) {
        aCoder.encode(identifier, forKey: "identifier")
        aCoder.encode(title, forKey: "title")
        aCoder.encode(link, forKey: "link")
        aCoder.encode(date, forKey: "date")
        aCoder.encode(updated, forKey: "updated")
        aCoder.encode(summary, forKey: "summary")
        aCoder.encode(content, forKey: "content")
        aCoder.encode(author, forKey: "author")
    }
    
    override public var description: String {
        let str = "RSSFeedItem: " + (title ?? "") + (date != nil ? " - \(date!)" : "")
        
        return str
    }
}
