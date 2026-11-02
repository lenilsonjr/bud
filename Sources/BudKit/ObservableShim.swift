#if !canImport(Combine)
/// Linux has no Combine. These stand in for `ObservableObject` and `@Published` so a store that
/// declares them compiles and tests here; they do nothing, because no view observes them here.
public protocol ObservableObject: AnyObject {}

@propertyWrapper
public struct Published<Value> {
    public var wrappedValue: Value

    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}
#endif
