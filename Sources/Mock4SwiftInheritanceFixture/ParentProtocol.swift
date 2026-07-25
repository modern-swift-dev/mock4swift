import Mock4Swift

public protocol CrossTargetParent {
    func parentValue(_ input: Int) -> String
}

@Mockable
public protocol LibraryTargetChild: CrossTargetParent {
    func childValue() -> Int
}
