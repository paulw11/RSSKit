//
//  RSSFeedInfo.swift
//  RSSKit
//
//  Created by Quan Nguyen on 7/7/16.
//
//

import Foundation

public class RSSFeedInfo: NSObject, NSCoding {
    
    
    public var title:String?
    public var link:String?
    public var summary:String?
    public var url:URL?
    
    public override init() {
        super.init()
    }
    
    required public init(coder aDecoder: NSCoder) {
        title = aDecoder.decodeObject(forKey: "title") as? String
        link = aDecoder.decodeObject(forKey: "link") as? String
        summary = aDecoder.decodeObject(forKey: "summary") as? String
        url = aDecoder.decodeObject(forKey: "url") as? URL
    }
    
    public func encode(with aCoder: NSCoder) {
        aCoder.encode(title, forKey: "title")
        aCoder.encode(link, forKey: "link")
        aCoder.encode(summary, forKey: "summary")
        aCoder.encode(url, forKey: "url")
    }
    
    override public var description: String {
        let str = "RSSFeedInfo: " + (title ?? "")
        
        return str
    }
}
