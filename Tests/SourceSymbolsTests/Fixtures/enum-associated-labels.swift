enum Labels {
    case explicit(_ value: Int), escaped(`_`: String)
    case annotated(callback: @Sendable (Int, String) -> Void, value: [Int /* interior */] = [1, 2])
}
