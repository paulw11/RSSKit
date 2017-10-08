//
//  NSDate+InternetDateTime.swift
//
//  Created by Quan Nguyen on 6/27/16.
//  Copyright © 2016 Niteco, Inc. All rights reserved.
//

import Foundation

var _internetDateTimeFormatter:DateFormatter? = nil

enum DateFormatHint {
    case None
    case RFC822
    case RFC3339
}

extension Date {
    
    private static func internetDateTimeFormatter() -> DateFormatter {
        if _internetDateTimeFormatter == nil {
            let en_US_POSIX = Locale(identifier: "en_US_POSIX")
            _internetDateTimeFormatter = DateFormatter()
            _internetDateTimeFormatter?.locale = en_US_POSIX
            _internetDateTimeFormatter?.timeZone = TimeZone(secondsFromGMT: 0)
        }
        
        return _internetDateTimeFormatter!
    }
    
    static func dateFromInternetDateTimeString(_ dateString:String, formatHint hint:DateFormatHint) -> Date? {
        var date:Date? = nil
        
        if hint != .RFC3339 {
            // Try RFC822 first
            date = Date.dateFromRFC822String( dateString)
            if date == nil {
                date = Date.dateFromRFC3339String(dateString)
            }
        } else {
            // Try RFC3339 first
            date = Date.dateFromRFC3339String(dateString)
            if date == nil {
                date = Date.dateFromRFC822String(dateString)
            }
        }
        
        return date
    }
    
    static func dateFromRFC3339String(_ dateString:String) -> Date? {
        var date:Date? = nil
        
        let dateFormatter = Date.internetDateTimeFormatter()
        // Process date
        var RFC3339String = dateString.uppercased().replacingOccurrences(of: "Z", with: "-0000")
        // Remove colon in timezone as it breaks NSDateFormatter in iOS 4+
        
        if RFC3339String.characters.count > 20 {
            let range = Range<String.Index>(RFC3339String.index(RFC3339String.startIndex, offsetBy:20)..<RFC3339String.endIndex)
            
            RFC3339String = RFC3339String.replacingOccurrences(of:":", with:"", options: [],
                                                               range: range)
        }
        
        if date == nil { // 1996-12-19T16:39:57-0800
            dateFormatter.dateFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ssZZZ"
            date = dateFormatter.date(from: RFC3339String)
        }
        if date == nil { // 1937-01-01T12:00:27.87+0020
            dateFormatter.dateFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ss.SSSZZZ"
            date = dateFormatter.date(from: RFC3339String)
        }
        if date == nil { // 1937-01-01T12:00:27
            dateFormatter.dateFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ss"
            date = dateFormatter.date(from: RFC3339String)
        }
        
        return date
    }
    
    static func dateFromRFC822String(_ dateString:String) -> Date? {
        var date:Date? = nil
        
        let dateFormatter = Date.internetDateTimeFormatter()
        let RFC822String = dateString.uppercased()
        
        if RFC822String.range(of:",") != nil {
            if date == nil { // Sun, 19 May 2002 15:21:36 GMT
                dateFormatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss zzz"
                date = dateFormatter.date(from: RFC822String)
            }
            
            if date == nil { // Sun, 19 May 2002, 15:21 GMT
                dateFormatter.dateFormat = "EEE, d MMM yyyy HH:mm zzz"
                date = dateFormatter.date(from: RFC822String)
            }
            
            if date == nil { // Sun, 19 May 2002 15:21:36
                dateFormatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss"
                date = dateFormatter.date(from: RFC822String)
            }
            
            if date == nil { // Sun, 19 May 2002 15:21
                dateFormatter.dateFormat = "EEE, d MMM yyyy HH:mm"
                date = dateFormatter.date(from: RFC822String)
            }
        } else {
            if date == nil { // 19 May 2002 15:21:36 GMT
                dateFormatter.dateFormat = "d MMM yyyy HH:mm:ss zzz"
                date = dateFormatter.date(from: RFC822String)
            }
            
            if date == nil { // 19 May 2002 15:21 GMT
                dateFormatter.dateFormat = "d MMM yyyy HH:mm zzz"
                date = dateFormatter.date(from: RFC822String)
            }
            
            if date == nil { // 19 May 2002 15:21:36
                dateFormatter.dateFormat = "d MMM yyyy HH:mm:ss"
                date = dateFormatter.date(from: RFC822String)
            }
            
            if date == nil { // 19 May 2002 15:21
                dateFormatter.dateFormat = "d MMM yyyy HH:mm"
                date = dateFormatter.date(from: RFC822String)
            }
        }
        
        return date
    }
}
