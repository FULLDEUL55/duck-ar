import Combine
import Foundation

// `PerceivedObject` itself is owned by the Perception module. This protocol
// is the contract the behavior coordinator depends on, kept free of any
// ARKit/Vision types so the perception backend can swap freely.
protocol PerceivedObjectSource {
    var perceivedObjectsPublisher: AnyPublisher<PerceivedObject, Never> { get }
}
