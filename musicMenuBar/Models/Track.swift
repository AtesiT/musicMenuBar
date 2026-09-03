import Foundation

struct Track: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let url: URL
}
