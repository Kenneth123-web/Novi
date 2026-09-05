import SwiftUI

struct Author: Identifiable, Hashable {
    let id: String
    let name: String
    var noviID: String = ""
    var bio: String = ""
    var followers: Int = 0
    var following: Int = 0
    var liked: Int = 0
}

struct NoteTag: Identifiable, Hashable {
    let id = UUID()
    let text: String
}

/// A card in the feed. `ratio` is width ÷ height of the cover and is stored
/// rather than measured: the masonry has to know how tall a card will be
/// BEFORE it lays it out, and a two-column feed that guesses wrong bounces as
/// it scrolls.
struct Note: Identifiable, Hashable {
    let id: String
    let title: String
    let author: Author
    var likes: Int
    var ratio: CGFloat = 0.75
    var badge: Badge? = nil
    var body: String = ""
    var tags: [String] = []
    var collects: Int = 0
    var comments: Int = 0
    var photos: Int = 1
    var place: String? = nil
    var postedAt: String = ""

    enum Badge: Hashable {
        case hot          // 热点
        case live         // 直播中
        case video        // a play glyph in the cover's corner

        /// English catalog key; translated at the point of display.
        var label: String? {
            switch self {
            case .hot: return "Trending"
            case .live: return nil  // drawn as a flag on the cover instead
            case .video: return nil
            }
        }
    }

    /// Seed for the generated cover. Kept separate from `id` so a note's
    /// picture survives an id scheme change.
    var coverSeed: String { "cover-" + id }
}

struct Comment: Identifiable, Hashable {
    let id = UUID()
    let author: Author
    let text: String
    let time: String
    var likes: Int
    var replies: [Comment] = []
    var isAuthor: Bool = false
}

struct MessageThread: Identifiable, Hashable {
    let id = UUID()
    let author: Author
    let preview: String
    let time: String
    var unread: Int = 0
}
