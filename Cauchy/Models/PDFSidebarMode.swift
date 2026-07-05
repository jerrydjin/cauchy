import Foundation

enum SidebarContentMode: String, CaseIterable, Codable, Sendable {
    case thumbnails
    case tableOfContents
    case highlightsAndNotes
    case contactSheet

    var title: String {
        switch self {
        case .thumbnails: "Thumbnails"
        case .tableOfContents: "Table of Contents"
        case .highlightsAndNotes: "Highlights and Notes"
        case .contactSheet: "Contact Sheet"
        }
    }
}

enum PDFPageLayoutMode: String, CaseIterable, Codable, Sendable {
    case continuousScroll
    case singlePage
    case twoPages

    var title: String {
        switch self {
        case .continuousScroll: "Continuous Scroll"
        case .singlePage: "Single Page"
        case .twoPages: "Two Pages"
        }
    }
}
