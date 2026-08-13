import Mock4SwiftTesting
import Testing

@Test func ingAdapterReexportsCoreMockAPIs() {
    let count: Count = .exactly(1)
    #expect(count.matches(1))
}
