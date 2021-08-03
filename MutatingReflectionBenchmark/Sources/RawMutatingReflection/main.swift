import Benchmark  // .package(name: "Benchmark", url: "https://github.com/google/swift-benchmark.git", from: "0.1.0"),
import Foundation
import Runtime    // .package(url: "https://github.com/wickwirew/Runtime", from: "2.2.2"),

/// This benchmark compares different methods to inject a struct with `Content`.
/// The `ContentInjectable` protocol resembles Apodini's `RequestInjectable`.
/// Results can be found at the very end of this file.
/// 
/// The `Runtime` library is the same as used in Apodini.
/// 
/// 
/// There are two different concepts (that would require different treatment
/// of `Handler`s from Apodini's side), "Independent Value-Copies" and
/// "Live Initialization". Each concept can be implemented using different
/// techniques.
/// 
/// # Independent Value-Copies
/// 
/// Simple copies of the struct must hold the same information as the original. However,
/// it must also be possible to obtain a copy of the original struct that is independent of
/// previous copies and carries different information.
/// 
/// The benchmark repeats the following action to get a precise measurement:
/// 
/// 1. `Content` `a` is decoded from a JSON string
/// 2. `Content` `b` is decoded from another JSON string
/// 3. A previously unused injectable is injected with `a`
/// 4. A direct copy of the same injectable is injected with `b`
/// 5. An assertion checks that the first copy holds
///    `a` and the second holds `b` (the assertion is implemented with
///    minimal overhead for all approaches)
/// 
/// Steps 1. and 2. are meant to set the performance-scores of injection in
/// relation to a task that is common in server side processing.
/// 
/// For benchmarks that are not marked "(with JSON Decoding)" steps 1. and 2. are
/// skipped. Instead `a` and `b` are defined as local constants.
/// 
/// 
/// ## Mutating modification without Reflection
/// 
/// This is the base-score. The `inject` function is implemented by directly assigning
/// the values to the according properties on the type. This is entirely impractical
/// for Apodini.
/// 
/// 
/// ## Mutating Runtime Reflection
/// 
/// This is the approach currently implemented in Apodini.
/// 
/// 
/// ## Mutating Prepared Runtime Reflection
/// 
/// This is based on the same library as "Mutating Runtime Reflection", but
/// caches every value possible in a global cache. That is, expensive calls to
/// determine the memory layout of the type are only performed once at the beginning
/// and reused for all follow-up injections.
/// 
/// 
/// ## Codable Based Traversable
/// 
/// This approach uses the InstanceCoding concept. It only encodes to an array once
/// at the beginning, storing this array in a global cache. Decoding is performed for
/// every request.
/// 
/// 
/// ## Mutating modification without Reflection (Generic)
/// 
/// This approach is similar to "Mutating modification without Reflection" but does
/// does not abuse the fact that in this benchmark the implementation knows what
/// value on the `Content` must be injected into what property of the struct.
/// 
/// 
/// 
/// # Independent Value-Copies
/// 
/// Each usage of the `Handler` uses its own instance. Instead of storing an
/// instance of the `Handler` that is copied, a closure returning a new instance
/// on each call is used.
/// 
/// The benchmark repeats the following action to get a precise measurement:
/// 
/// 1. `Content` `a` is decoded from a JSON string
/// 2. `Content` `b` is decoded from another JSON string
/// 3. A new injectable is initialized and injected with `a`
/// 4. A new injectable is initialized and injected with `b`
/// 5. An assertion checks that the first instance holds
///    `a` and the second holds `b` (the assertion is implemented with
///    minimal overhead for all approaches)
/// 
/// Steps 1. and 2. are meant to set the performance-scores of injection in
/// relation to a task that is common in server side processing.
/// 
/// For benchmarks that are not marked "(with JSON Decoding)" steps 1. and 2. are
/// skipped. Instead `a` and `b` are defined as local constants.
/// 
/// 
/// ## Live Initialization
/// 
/// The property wrappers on this `Handler` are reference-types. On initialization
/// they append themselves to a global array variable. Iterating over this array
/// variable provides direct access to the `Handler`'s properties.
/// 
/// If implemented in Apodini, the global array would have to be implmented as a
/// ThreadSpecificVariable. Furthermore, the order of property-initialization
/// has to be asserted:
/// 
/// Initializers with side effects are deterministic in Apodini, thus the order
/// never changes, however not all initialized property wrappers end up as a
/// property. Take the following example.
/// 
/// @propertyWrapper
/// struct Printed<T> {
///     var wrappedValue: T
///    
///     init(wrappedValue: T) {
///         print(wrappedValue)
///         self.wrappedValue = wrappedValue
///     }
/// }
/// 
/// struct MyStruct {
///     @Printed var one = 1
///     @Printed var two = 2
///     @Printed var three = 3
///     @Printed var four = 4
///     @Printed var five = 5
/// 
///     init(override: Int) {
///         _five = Printed(wrappedValue: override)	
///     }
/// }
/// 
/// _ = MyStruct(override: 100)
/// 
/// This code would always print 1,2,3,4,5,100. However, when iterating over
/// `MyStruct`'s properties, you would only encounter 1,2,3,4 and 100.
/// 
/// Such irregularities have to be captured at startup-time (using Mirror). The
/// runtime-behavior has to be adapted according to that (but that does not require
/// usage of reflection). Furthermore, Apodini should validate in DEBUG mode,
/// that this mapping between initialized property wrappers and the properties
/// present on the struct does not change. This can be done using Mirror. Again,
/// this can be disabled in production systems.
/// 


// MARK: Basics

class SomeClass: Equatable, Codable {
    let string: String
    
    init(string: String) {
        self.string = string
    }
    
    static func == (lhs: SomeClass, rhs: SomeClass) -> Bool {
        lhs.string == rhs.string
    }
}

/// A content just contains information of different type, which represents input for
/// `Handler`s in a dynamic web server. It uses various value, and one reference type.
struct Content: Codable {
    let string: String
    let int: Int
    let optional: Int?
    let reference: SomeClass
}

protocol ContentInjectable {
    mutating func inject(_ content: Content) throws
}

protocol Assertable {
    // checks if self was injected with `content`
    func assertInjection(with content: Content) -> Bool
}

// MARK: Mutating modification without Reflection

struct NoReflectionHandler: ContentInjectable, Assertable {
    var string: String
    var int: Int
    var optional: Int?
    var reference: SomeClass
    
    mutating func inject(_ content: Content) {
        self.string = content.string
        self.int = content.int
        self.optional = content.optional
        self.reference = content.reference
    }
    
    func assertInjection(with content: Content) -> Bool {
        content.string == string && content.int == int && content.optional == optional && content.reference == reference
    }
}

// MARK: Mutating modification without Reflection (Generic)

struct NoReflectionHandlerGeneric: ContentInjectable, Assertable {
    @MutatingStore var string: String
    @MutatingStore var int: Int
    @MutatingStore var optional: Int?
    @MutatingStore var reference: SomeClass
    
    mutating func inject(_ content: Content) {
        self._string.inject(content)
        self._int.inject(content)
        self._optional.inject(content)
        self._reference.inject(content)
    }
    
    func assertInjection(with content: Content) -> Bool {
        content.string == string && content.int == int && content.optional == optional && content.reference == reference
    }
}


// MARK: Mutating Runtime Reflection

@propertyWrapper
struct MutatingStore<Value>: ContentInjectable {
    var wrappedValue: Value
    
    mutating func inject(_ content: Content) {
        switch Value.self {
        case is String.Type:
            self.wrappedValue = content.string as! Value
        case is Int.Type:
            self.wrappedValue = content.int as! Value
        case is Int?.Type:
            self.wrappedValue = content.optional as! Value
        case is SomeClass.Type:
            self.wrappedValue = content.reference as! Value
        default:
            fatalError()
        }
    }
}

struct MutatingRuntimeReflectionBasedHandler: ContentInjectable, Assertable {
    @MutatingStore var string: String
    @MutatingStore var int: Int
    @MutatingStore var optional: Int?
    @MutatingStore var reference: SomeClass
    
    mutating func inject(_ content: Content) throws {
        guard let info = try? typeInfo(of: Self.self) else {
            fatalError("Applying operation on all properties of \((try? typeInfo(of: ContentInjectable.self))?.name ?? "Unknown Type") on element \(self) failed.")
        }

        for property in info.properties {
            guard let child = try? property.get(from: self) else {
                fatalError("Applying operation on all properties of \((try? typeInfo(of: ContentInjectable.self))?.name ?? "Unknown Type") failed.")
            }
            if var target = child as? ContentInjectable {
                try target.inject(content)
                property.unsafeSet(
                    value: target,
                    on: &self,
                    printing: "Applying operation on all properties of \((try? typeInfo(of: ContentInjectable.self))?.name ?? "Unknown Type") failed.")
            }
        }
    }
    
    
    func assertInjection(with content: Content) -> Bool {
        content.string == string && content.int == int && content.optional == optional && content.reference == reference
    }
}

extension Runtime.PropertyInfo {
    @inlinable
    func unsafeSet<TObject>(value: Any, on object: inout TObject, printing errorMessage: @autoclosure () -> String) {
        do {
            try self.set(value: value, on: &object)
        } catch {
            fatalError(errorMessage())
        }
    }
}

// MARK: Mutating Prepared Runtime Reflection

extension PropertyInfo: Hashable {
    public func hash(into hasher: inout Hasher) {
        self.name.hash(into: &hasher)
    }
}

struct MutatingPreparedRuntimeReflectionBasedHandler: ContentInjectable, Assertable {
    static var infoCache: TypeInfo?
    static var childCache: [(PropertyInfo, ContentInjectable)]?
    
    @MutatingStore var string: String
    @MutatingStore var int: Int
    @MutatingStore var optional: Int?
    @MutatingStore var reference: SomeClass
    
    mutating func inject(_ content: Content) throws {
        var i = Self.infoCache
        if i == nil {
            i = try? typeInfo(of: Self.self)
            Self.infoCache = i
        }
        
        guard let info = i else {
            fatalError("Applying operation on all properties of \((try? typeInfo(of: ContentInjectable.self))?.name ?? "Unknown Type") on element \(self) failed.")
        }
        
        var children = Self.childCache
        if children == nil {
            children = []
            for property in info.properties {
                guard let child = try? property.get(from: self) else {
                    fatalError("Applying operation on all properties of \((try? typeInfo(of: ContentInjectable.self))?.name ?? "Unknown Type") failed.")
                }
                if let c = child as? ContentInjectable {
                    children?.append((property, c))
                }
            }
            Self.childCache = children
        }

        for i in children!.indices {
            var (property, child) = children![i]
            try child.inject(content)
            property.unsafeSet(value: child, on: &self, printing: "Applying operation on all properties of \((try? typeInfo(of: ContentInjectable.self))?.name ?? "Unknown Type") failed.")
            children![i].1 = child
        }
    }
    
    
    func assertInjection(with content: Content) -> Bool {
        content.string == string && content.int == int && content.optional == optional && content.reference == reference
    }
}

// MARK: Codable Based Traversable

struct InstanceCodableBasedHandler: InstanceCodable, Assertable {
    static var injector: Injector?
    
    @Parameter var string: String
    @Parameter var int: Int
    @Parameter var optional: Int?
    @Parameter var reference: SomeClass
    
    func assertInjection(with content: Content) -> Bool {
        content.string == string && content.int == int && content.optional == optional && content.reference == reference
    }
}

protocol Property {}

protocol Activatable {
    mutating func activate()
}

protocol InstanceCoder: Encoder, Decoder {
    func singleInstanceContainer() throws -> SingleValueInstanceContainer
}

protocol SingleValueInstanceContainer: SingleValueDecodingContainer, SingleValueEncodingContainer {
    func decode<T>(_ type: T.Type) throws -> T
    func encode<T>(_ value: T) throws
}

protocol InstanceCodable: Codable { }

enum InstanceCodingError: Error {
    case instantializedUsingNonInstanceCoder
    case encodedUsingNonInstanceCoder
    case notImplemented
    case badType
}

@propertyWrapper
struct Parameter<T>:  ContentInjectable, InstanceCodable {
    var _value: T?
    
    var wrappedValue: T {
        get {
            guard let value = _value else {
                fatalError()
            }
            return value
        }
        set {
            _value = newValue
        }
    }
    
    init() { }
    
    mutating func inject(_ value: Content) {
        switch T.self {
        case is Int.Type:
            self._value = (value.int as! T)
        case is String.Type:
            self._value = (value.string as! T)
        case is Int?.Type:
            self._value = (value.optional as! T)
        case is SomeClass.Type:
            self._value = (value.reference as! T)
        default:
            fatalError()
        }
    }
    
    init(from decoder: Decoder) throws {
        guard let ic = decoder as? InstanceCoder else {
            throw InstanceCodingError.instantializedUsingNonInstanceCoder
        }
        
        let container = try ic.singleInstanceContainer()
        let injectedValue = try container.decode(Parameter<T>.self)
        
        self = injectedValue
    }
    
    func encode(to encoder: Encoder) throws {
        guard let ic = encoder as? InstanceCoder else {
            throw InstanceCodingError.encodedUsingNonInstanceCoder
        }
        
        let container = try ic.singleInstanceContainer()
        try container.encode(self)
    }
}

class Injector: InstanceCoder {
    var codingPath: [CodingKey] = []
    
    var userInfo: [CodingUserInfoKey : Any] = [:]
    
    var valueToInject: Content
    
    var store: [InstanceCodable] = []
    
    var count: Int = 0
    
    init(valueToInject: Content) {
        self.valueToInject = valueToInject
    }
    
    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key : CodingKey {
        KeyedEncodingContainer(KeyedInstanceContainer(injector: self))
    }
    
    func unkeyedContainer() -> UnkeyedEncodingContainer {
        UnkeyedInstanceEncodingContainer(injector: self)
    }
    
    func singleValueContainer() -> SingleValueEncodingContainer {
        InstanceContainer(injector: self)
    }
    
    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
        KeyedDecodingContainer(KeyedInstanceContainer(injector: self))
    }
    
    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        UnkeyedInstanceDecodingContainer(injector: self)
    }
    
    func singleValueContainer() throws -> SingleValueDecodingContainer {
        InstanceContainer(injector: self)
    }
    
    func singleInstanceContainer() throws -> SingleValueInstanceContainer {
        InstanceContainer(injector: self)
    }
    
    func mutate(parameter: inout ContentInjectable) throws {
        try parameter.inject(self.valueToInject)
    }
    
    func reset() {
        self.count = 0
    }
}

struct UnkeyedInstanceDecodingContainer: UnkeyedDecodingContainer {
    let injector: Injector
    
    var codingPath: [CodingKey] {
        get {
            injector.codingPath
        }
        set {
            injector.codingPath = newValue
        }
    }
    
    var count: Int? = nil
    
    var isAtEnd: Bool = false
    
    var currentIndex: Int = 0
    
    mutating func decodeNil() throws -> Bool {
        false
    }

    mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        try injector.container(keyedBy: type)
    }
    
    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        try injector.unkeyedContainer()
    }
    
    mutating func superDecoder() throws -> Decoder {
        injector
    }
    
    mutating func decode<T>(_ type: T.Type) throws -> T {
        guard T.self is InstanceCodable.Type else {
            throw InstanceCodingError.notImplemented
        }
        
        let next = injector.store[injector.count]
        injector.count += 1
        
        guard let typed = next as? T else {
            throw InstanceCodingError.badType
        }
        
        if var parameter = typed as? ContentInjectable {
            try injector.mutate(parameter: &parameter)
            return parameter as! T
        } else {
            return typed
        }
    }
}

struct UnkeyedInstanceEncodingContainer: UnkeyedEncodingContainer {
    let injector: Injector
    
    var codingPath: [CodingKey] {
        get {
            injector.codingPath
        }
        set {
            injector.codingPath = newValue
        }
    }
    
    var count: Int = 0
    
    mutating func encodeNil() throws {
        throw InstanceCodingError.notImplemented
    }
    
    mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
        injector.container(keyedBy: keyType)
    }
    
    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        injector.unkeyedContainer()
    }
    
    mutating func superEncoder() -> Encoder {
        injector
    }
    
    mutating func encode<T>(_ value: T) throws {
        guard let typed = value as? InstanceCodable else {
            throw InstanceCodingError.notImplemented
        }
        
        injector.store.append(typed)
    }
}

struct KeyedInstanceContainer<K: CodingKey>: KeyedEncodingContainerProtocol, KeyedDecodingContainerProtocol {
    mutating func encodeNil(forKey key: K) throws {
        throw InstanceCodingError.notImplemented
    }
    
    mutating func encode<T>(_ value: T, forKey key: K) throws {
        guard let typed = value as? InstanceCodable else {
            throw InstanceCodingError.notImplemented
        }
        
        injector.store.append(typed)
    }
    
    var allKeys: [K] {
        return []
    }
    
    mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: K) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
        injector.container(keyedBy: keyType)
    }
    
    mutating func nestedUnkeyedContainer(forKey key: K) -> UnkeyedEncodingContainer {
        injector.unkeyedContainer()
    }
    
    mutating func superEncoder() -> Encoder {
        injector
    }
    
    mutating func superEncoder(forKey key: K) -> Encoder {
        injector
    }
    
    func contains(_ key: K) -> Bool {
        return false
    }
    
    func decodeNil(forKey key: K) throws -> Bool {
        false
    }
    
    func decode<T>(_ type: T.Type, forKey key: K) throws -> T {
        guard T.self is InstanceCodable.Type else {
            throw InstanceCodingError.notImplemented
        }
        
        let next = injector.store[injector.count]
        injector.count += 1
        
        guard let typed = next as? T else {
            throw InstanceCodingError.badType
        }
        
        if var parameter = typed as? ContentInjectable {
            try injector.mutate(parameter: &parameter)
            return parameter as! T
        } else {
            return typed
        }
    }
    
    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: K) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        try injector.container(keyedBy: type)
    }
    
    func nestedUnkeyedContainer(forKey key: K) throws -> UnkeyedDecodingContainer {
        try injector.unkeyedContainer()
    }
    
    func superDecoder() throws -> Decoder {
        injector
    }
    
    func superDecoder(forKey key: K) throws -> Decoder {
        injector
    }
    
    typealias Key = K
    
    let injector: Injector
    
    var codingPath: [CodingKey] {
        get {
            injector.codingPath
        }
        set {
            injector.codingPath = newValue
        }
    }
}

struct InstanceContainer: SingleValueInstanceContainer {
    let injector: Injector
    
    var codingPath: [CodingKey] {
        get {
            injector.codingPath
        }
        set {
            injector.codingPath = newValue
        }
    }
    
    func decode<T>(_ type: T.Type) throws -> T {
        guard T.self is InstanceCodable.Type else {
            throw InstanceCodingError.notImplemented
        }
        
        let next = injector.store[injector.count]
        injector.count += 1
        
        guard let typed = next as? T else {
            throw InstanceCodingError.badType
        }
        
        if var parameter = typed as? ContentInjectable {
            try injector.mutate(parameter: &parameter)
            return parameter as! T
        } else {
            return typed
        }
    }
    
    func encode<T>(_ value: T) throws {
        guard let typed = value as? InstanceCodable else {
            throw InstanceCodingError.notImplemented
        }
        
        injector.store.append(typed)
    }
    
    func decodeNil() -> Bool {
        false
    }
    
    mutating func encodeNil() throws {
        throw InstanceCodingError.notImplemented
    }
}

extension InstanceCodableBasedHandler: ContentInjectable {
    mutating func inject(_ content: Content) throws {
        var injector: Injector
        if let i = Self.injector {
            injector = i
        } else {
            injector = Injector(valueToInject: Content(string: "x", int: -1, optional: -1, reference: SomeClass(string: "x")))
            try self.encode(to: injector)
            Self.injector = injector
        }
        injector.valueToInject = content
        self = try InstanceCodableBasedHandler(from: injector)
        injector.reset()
    }
}

// MARK: Live Initialization intead of Mutation

struct LiveInitializationHandler: ContentInjectable, Assertable {
    @RegisteringStore var string: String
    @RegisteringStore var int: Int
    @RegisteringStore var optional: Int?
    @RegisteringStore var reference: SomeClass
    
    mutating func inject(_ content: Content) throws {
        for var injectable in registeringStoreCollector {
            try injectable.inject(content)
        }
        registeringStoreCollector.removeAll(keepingCapacity: true)
    }
    
    func assertInjection(with content: Content) -> Bool {
        content.string == string && content.int == int && content.optional == optional && content.reference == reference
    }
}

var registeringStoreCollector: [ContentInjectable] = []

@propertyWrapper
class RegisteringStore<Value>: ContentInjectable {
    init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
        registeringStoreCollector.append(self)
    }

    var wrappedValue: Value
    
    func inject(_ content: Content) {
        switch Value.self {
        case is String.Type:
            self.wrappedValue = content.string as! Value
        case is Int.Type:
            self.wrappedValue = content.int as! Value
        case is Int?.Type:
            self.wrappedValue = content.optional as! Value
        case is SomeClass.Type:
            self.wrappedValue = content.reference as! Value
        default:
            fatalError()
        }
    }
}



// MARK: Benchmark Definitions

func inject<I>(_ a: Content, _ b: Content, into injectable: I) throws where I: ContentInjectable, I: Assertable {
    var ia = injectable
    try ia.inject(a)
    var ib = ia
    try ib.inject(b)
    var worked = true
    worked = ia.assertInjection(with: a) && worked
    worked = ib.assertInjection(with: b) && worked
    precondition(worked)
}

func injectLiveInitialization<I>(_ a: Content, _ b: Content, into injectable: () -> I) throws where I: ContentInjectable, I: Assertable {
    var ia = injectable()
    try ia.inject(a)
    var ib = injectable()
    try ib.inject(b)
    var worked = true
    worked = ia.assertInjection(with: a) && worked
    worked = ib.assertInjection(with: b) && worked
    precondition(worked)
}

let jsonA = """
{
    "string": "a",
    "int": 0,
    "optional": 0,
    "reference": {
        "string": "a"
    }
}
"""

let jsonB = """
{
    "string": "b",
    "int": 1,
    "reference": {
        "string": "b"
    }
}
"""
let trash = Content(string: "x", int: -1, optional: -1, reference: SomeClass(string: "x"))



// MARK: Benchmarks with Payload Decoding

var injectable1 = NoReflectionHandler(string: "x", int: -1, optional: -1, reference: SomeClass(string: "x"))
injectable1.inject(trash)
benchmark("Mutating modification without Reflection (with JSON Decoding)") {
    let a = try! JSONDecoder().decode(Content.self, from: jsonA.data(using: .utf8)!)
    let b = try! JSONDecoder().decode(Content.self, from: jsonB.data(using: .utf8)!)
    try! inject(a, b, into: injectable1)
}

var injectable2 = MutatingRuntimeReflectionBasedHandler(string: "x", int: -1, optional: -1, reference: SomeClass(string: "x"))
try! injectable2.inject(trash)
benchmark("Mutating Runtime Reflection (with JSON Decoding)") {
    let a = try! JSONDecoder().decode(Content.self, from: jsonA.data(using: .utf8)!)
    let b = try! JSONDecoder().decode(Content.self, from: jsonB.data(using: .utf8)!)
    try! inject(a, b, into: injectable2)
}

var injectable4 = MutatingPreparedRuntimeReflectionBasedHandler(string: "x", int: -1, optional: -1, reference: SomeClass(string: "x"))
try! injectable4.inject(trash)
benchmark("Mutating Prepared Runtime Reflection (with JSON Decoding)") {
    let a = try! JSONDecoder().decode(Content.self, from: jsonA.data(using: .utf8)!)
    let b = try! JSONDecoder().decode(Content.self, from: jsonB.data(using: .utf8)!)
    try! inject(a, b, into: injectable4)
}

var injectable5 = InstanceCodableBasedHandler()
try injectable5.inject(trash)
benchmark("Codable Based Traversable (with JSON Decoding)") {
    let a = try! JSONDecoder().decode(Content.self, from: jsonA.data(using: .utf8)!)
    let b = try! JSONDecoder().decode(Content.self, from: jsonB.data(using: .utf8)!)
    try inject(a, b, into: injectable5)
}

var injectable6 = NoReflectionHandlerGeneric(string: "x", int: -1, optional: -1, reference: SomeClass(string: "x"))
injectable6.inject(trash)
benchmark("Mutating modification without Reflection (Generic) (with JSON Decoding)") {
    let a = try! JSONDecoder().decode(Content.self, from: jsonA.data(using: .utf8)!)
    let b = try! JSONDecoder().decode(Content.self, from: jsonB.data(using: .utf8)!)
    try! inject(a, b, into: injectable6)
}

var injectable7 = { LiveInitializationHandler(string: "x", int: -1, optional: -1, reference: SomeClass(string: "x")) }
benchmark("Live Initialization (with JSON Decoding)") {
    let a = try! JSONDecoder().decode(Content.self, from: jsonA.data(using: .utf8)!)
    let b = try! JSONDecoder().decode(Content.self, from: jsonB.data(using: .utf8)!)
    try! injectLiveInitialization(a, b, into: injectable7)
}

// MARK: Benchmarks without Payload Decoding

let n_a = try! JSONDecoder().decode(Content.self, from: jsonA.data(using: .utf8)!)
let n_b = try! JSONDecoder().decode(Content.self, from: jsonB.data(using: .utf8)!)

var n_injectable1 = NoReflectionHandler(string: "x", int: -1, optional: -1, reference: SomeClass(string: "x"))
n_injectable1.inject(trash)
// benchmark
benchmark("Mutating modification without Reflection") {
    try! inject(n_a, n_b, into: n_injectable1)
}

var n_injectable2 = MutatingRuntimeReflectionBasedHandler(string: "x", int: -1, optional: -1, reference: SomeClass(string: "x"))
try! n_injectable2.inject(trash)
benchmark("Mutating Runtime Reflection") {
    try! inject(n_a, n_b, into: n_injectable2)
}

var n_injectable4 = MutatingPreparedRuntimeReflectionBasedHandler(string: "x", int: -1, optional: -1, reference: SomeClass(string: "x"))
try! n_injectable4.inject(trash)
benchmark("Mutating Prepared Runtime Reflection") {
    try! inject(n_a, n_b, into: n_injectable4)
}

var n_injectable5 = InstanceCodableBasedHandler()
try n_injectable5.inject(trash)
benchmark("Codable Based Traversal") {
    try inject(n_a, n_b, into: n_injectable5)
}

var n_injectable6 = NoReflectionHandlerGeneric(string: "x", int: -1, optional: -1, reference: SomeClass(string: "x"))
n_injectable6.inject(trash)
// benchmark
benchmark("Mutating modification without Reflection (Generic)") {
    try! inject(n_a, n_b, into: n_injectable6)
}

var n_injectable7 = { LiveInitializationHandler(string: "x", int: -1, optional: -1, reference: SomeClass(string: "x")) }
benchmark("Live Initialization") {
    try! injectLiveInitialization(n_a, n_b, into: n_injectable7)
}

Benchmark.main()


// MARK: Results

// Hardware:
// MacBook Pro (13-inch, 2017, Two Thunderbolt 3 ports)
// 2.3 GHz Dual-Core Intel Core i5
// 8 GB 2133 MHz LPDDR3


// name                                                                    time         std         iterations
// -----------------------------------------------------------------------------------------------------------
// Mutating modification without Reflection (with JSON Decoding)           28030.000 ns +/-  54.57 %       34883
// Mutating Runtime Reflection (with JSON Decoding)                        49971.000 ns +/-  88.20 %       21924
// Mutating Prepared Runtime Reflection (with JSON Decoding)               32724.500 ns +/-  68.95 %       26922
// Codable Based Traversable (with JSON Decoding)                          34271.000 ns +/-  60.61 %       31185
// Mutating modification without Reflection (Generic) (with JSON Decoding) 28402.000 ns +/-  72.23 %       37078
// Live Initialization (with JSON Decoding)                                30911.000 ns +/-  72.69 %       30021
// Mutating modification without Reflection                                   31.000 ns +/- 1660.69 %    1000000
// Mutating Runtime Reflection                                             15379.000 ns +/-  98.23 %       72812
// Mutating Prepared Runtime Reflection                                     2966.000 ns +/- 165.92 %      360254
// Codable Based Traversal                                                  4528.000 ns +/- 722.30 %      251790
// Mutating modification without Reflection (Generic)                        190.000 ns +/- 243.73 %     1000000
// Live Initialization                                                      1922.000 ns +/- 203.22 %      594699