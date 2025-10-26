//
//  AtomParser.swift
//  VibeRSS_Test
//
//  Created by Thien Ly on 10/26/25.
//


// FILE: Networking/AtomParser.swift
// PURPOSE: XMLParser-based Atom parser -> [FeedItem]
// SAFE TO EDIT: Yes, but be careful with tag handling and heuristics

import Foundation

final class AtomParser: NSObject, XMLParserDelegate {
    private var items: [FeedItem] = []
    private var currentTitle = ""
    private var currentLink: URL?
    private var currentSummary = ""
    private var currentUpdated: Date?
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
        if currentElement == "entry" { resetItem() }
        if currentElement == "link" {
            if let rel = attributeDict["rel"], rel.lowercased() == "enclosure",
               let type = attributeDict["type"], type.lowercased().hasPrefix("image"),
               let href = attributeDict["href"], let u = URL(string: href) {
                currentThumbnail = currentThumbnail ?? u
            } else if let href = attributeDict["href"], let url = URL(string: href) {
                currentLink = currentLink ?? url
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
        case "summary", "content": currentSummary += string
        case "updated", "published":
            currentUpdated = ISO8601DateFormatter().date(from: string.trimmingCharacters(in: .whitespacesAndNewlines))
        case "name": currentAuthor = (currentAuthor ?? "") + string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName.lowercased() == "entry" {
            if let link = currentLink {
                var thumb = currentThumbnail
                if thumb == nil {
                    thumb = extractFirstImageURL(from: currentSummary, relativeTo: link)
                }
                let title = currentTitle.trimmed()
                let summary = currentSummary.trimmedHTML()
                let author = currentAuthor?.trimmed()
                items.append(FeedItem(title: title, link: link, summary: summary, pubDate: currentUpdated, author: author, thumbnailURL: thumb))
            }
            resetItem()
        }
        currentElement = ""
    }

    private func resetItem() {
        currentTitle = ""
        currentLink = nil
        currentSummary = ""
        currentUpdated = nil
        currentAuthor = nil
        currentThumbnail = nil
    }
}