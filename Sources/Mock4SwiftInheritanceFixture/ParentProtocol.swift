import Mock4Swift

public protocol CrossTargetParent {
    func parentValue(_ input: Int) -> String
}

@Mockable public protocol LibraryTargetChild: CrossTargetParent {
    static func sharedValue() -> Int
    func childValue() -> Int
}
