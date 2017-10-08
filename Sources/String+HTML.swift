//
//  String+HTML.swift
//
//  Created by Quan Nguyen on 7/4/16.
//  Copyright © 2016 Niteco, Inc. All rights reserved.
//

import Foundation

extension String {
    public func stringByConvertingHTMLToPlainText() -> String {
        // Character sets
        let stopCharacters = CharacterSet(charactersIn: String(format: "< \t\n\r%C%C%C%C", 0x0085, 0x000C, 0x2028, 0x2029))
        let newLineAndWhitespaceCharacters = CharacterSet(charactersIn: String(format: " \t\n\r%C%C%C%C", 0x0085, 0x000C, 0x2028, 0x2029))
        let tagNameCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        
        // Scan and find all tags
        let result = NSMutableString(capacity: self.utf16.count)
        let scanner = Scanner(string: self)
        scanner.charactersToBeSkipped = nil
        scanner.caseSensitive = true
        var str:NSString? = nil, tagName:NSString? = nil
        var replaceTagWithSpace = true
        
        repeat {
            
            // Scan up to the start of a tag or whitespace
            if scanner.scanUpToCharacters(from: stopCharacters, into: &str) {
                result.append(str! as String)
                str = nil // reset
            }
            
            // Check if we've stopped at a tag/comment or whitespace
            if scanner.scanString("<", into: nil) {
                // Stoppped at a comment, script tag, or other tag
                if scanner.scanString("!--", into: nil) {
                    // Comment
                    scanner.scanUpTo("-->", into: nil)
                    scanner.scanString("-->", into: nil)
                } else if scanner.scanString("script", into: nil) {
                    // Script tag where things don't need escaping!
                    scanner.scanUpTo("</script>", into: nil)
                    scanner.scanString("</script>", into: nil)
                } else {
                    // Tag - remove and replace with space unless it's
                    // a closing inline tag then dont replace with a space
                    if scanner.scanString("/", into: nil) {
                        // Closing tag - replace with space unless it's inline
                        tagName = nil
                        replaceTagWithSpace = true
                        if scanner.scanCharacters(from: tagNameCharacters, into: &tagName) {
                            let tagNameInLowercase = tagName?.lowercased
                            
                            replaceTagWithSpace = (tagNameInLowercase != "a" &&
                                                   tagNameInLowercase != "b" &&
                                                   tagNameInLowercase != "i" &&
                                                   tagNameInLowercase != "q" &&
                                                   tagNameInLowercase != "span" &&
                                                   tagNameInLowercase != "em" &&
                                                   tagNameInLowercase != "strong" &&
                                                   tagNameInLowercase != "cite" &&
                                                   tagNameInLowercase != "abbr" &&
                                                   tagNameInLowercase != "acronym" &&
                                                   tagNameInLowercase != "label")
                        }
                        
                        // Replace tag with string unless it was an inline
                        if replaceTagWithSpace && result.length > 0 && !scanner.isAtEnd {
                            result.append(" ")
                        }
                    }
                    
                    // Scan past tag
                    scanner.scanUpTo(">", into: nil)
                    scanner.scanString(">", into: nil)
                }
            } else {
                // Stopped at whitespace - replace all whitespace and newlines with a space
                if scanner.scanCharacters(from: newLineAndWhitespaceCharacters, into: nil) {
                    if result.length > 0 && !scanner.isAtEnd {
                        result.append(" ")
                    }
                }
            }
        } while !scanner.isAtEnd
        
        // Cleanup
        
        // Decode HTML entities and return
        let retString = (result as String).stringByDecodingHTMLEntities()
        
        return retString
    }
    
    public func stringByDecodingHTMLEntities() -> String {
        return self.gtm_stringByUnescapingFromHTML()
    }
    
    public func stringByEncodingHTMLEntities() -> String {
        return self.gtm_stringByEscapingForAsciiHTML()
    }
}
