//
//  RSSParser.swift
//  VibeRSS_Test
//
//  Created by Thien Ly on 10/26/25.
//


// FILE: Networking/RSSParser.swift
// PURPOSE: XMLParser-based RSS parser -> [FeedItem]
// SAFE TO EDIT: Yes, but be careful with tag handling and heuristics

import Foundation

final class RSSParser: NSObject, XMLParserDelegate {
    private var items: [FeedItem] = []
    private var currentTitle = ""
    private var currentLink: URL?
    private var currentDescription = ""
    private var currentPubDate: Date?
    private var currentAuthor: String?
    private var currentThumbnail: URL?
    private var currentElement = ""

    func parse(data: Data) throws -> [FeedItem] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { throw FeedError.parseFailed }
        return items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName.lowercased()
        if currentElement == "item" { resetItem() }
        if currentElement == "link", let href = attributeDict["href"], let url = URL(string: href) {
            currentLink = url // some feeds put link in <link href="..."/>
        }
        if currentElement == "enclosure" {
            if let type = attributeDict["type"], type.lowercased().hasPrefix("image"),
               let href = attributeDict["url"], let u = URL(string: href) {
                currentThumbnail = currentThumbnail ?? u
            }
        }
        if currentElement == "media:thumbnail" {
            if let href = attributeDict["url"], let u = URL(string: href) {
                currentThumbnail = currentThumbnail ?? u
            }
        }
        if currentElement == "media:content" {
            if let type = attributeDict["type"], type.lowercased().hasPrefix("image"),
               let href = attributeDict["url"], let u = URL(string: href) {
                currentThumbnail = currentThumbnail ?? u
            } else if let medium = attributeDict["medium"], medium.lowercased() == "image",
                      let href = attributeDict["url"], let u = URL(string: href) {
                currentThumbnail = currentThumbnail ?? u
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        switch currentElement {
        case "title": currentTitle += string
        case "link":
            if currentLink == nil {
                currentLink = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        case "description", "summary", "content:encoded":
            currentDescription += string
        case "pubdate":
            currentPubDate = DateFormatter.vr_rfc822.dateFromCommonRSS(string.trimmingCharacters(in: .whitespacesAndNewlines))
        case "author", "dc:creator":
            currentAuthor = (currentAuthor ?? "") + string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName.lowercased() == "item" {
            if let link = currentLink {
                var thumb = currentThumbnail
                if thumb == nil {
                    thumb = extractFirstImageURL(from: currentDescription, relativeTo: link)
                }
                let title = currentTitle.vr_trimmed()
                let desc = currentDescription.vr_trimmedHTML()
                let author = currentAuthor?.vr_trimmed()
                items.append(FeedItem(title: title, link: link, summary: desc, pubDate: currentPubDate, author: author, thumbnailURL: thumb))
            }
            resetItem()
        }
        currentElement = ""
    }

    private func resetItem() {
        currentTitle = ""
        currentLink = nil
        currentDescription = ""
        currentPubDate = nil
        currentAuthor = nil
        currentThumbnail = nil
    }
}

