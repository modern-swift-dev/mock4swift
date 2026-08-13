/// Controls the values returned by unstubbed, nonthrowing instance requirements.
public enum MockDefaultPolicy: Sendable {
    case strict
    case void
    case voidAndOptional
}
