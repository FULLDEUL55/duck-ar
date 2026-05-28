import Foundation

enum DuckState: String, CaseIterable, Hashable {
    case idle
    case walking
    case lookingAround
    case pecking
    case sitting
}
