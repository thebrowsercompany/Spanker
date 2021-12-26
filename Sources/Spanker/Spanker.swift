import Foundation
import Hitch

public extension Data {
    @inlinable @inline(__always)
    func parse() -> Spanker.JsonElement? {
        return Spanker.parse(data: self)
    }
}

public extension Hitch {
    @inlinable @inline(__always)
    func parse() -> Spanker.JsonElement? {
        return Spanker.parse(hitch: self)
    }
}

public extension String {
    @inlinable @inline(__always)
    func parse() -> Spanker.JsonElement? {
        return Spanker.parse(string: self)
    }
}

public enum Spanker {

    public enum JsonType {
        case null
        case boolean
        case string
        case int
        case double
        case array
        case dictionary
    }

    public class JsonElement: CustomStringConvertible {

        @discardableResult
        @inlinable @inline(__always)
        public func json(hitch: Hitch) -> Hitch {
            let appendNull: () -> Void = {
                hitch.append(UInt8.n)
                hitch.append(UInt8.u)
                hitch.append(UInt8.l)
                hitch.append(UInt8.l)
            }
            switch type {
            case .null:
                appendNull()
            case .boolean:
                if let valueBool = valueBool {
                    if valueBool {
                        hitch.append(UInt8.t)
                        hitch.append(UInt8.r)
                        hitch.append(UInt8.u)
                        hitch.append(UInt8.e)
                    } else {
                        hitch.append(UInt8.f)
                        hitch.append(UInt8.a)
                        hitch.append(UInt8.l)
                        hitch.append(UInt8.s)
                        hitch.append(UInt8.e)
                    }
                } else {
                    appendNull()
                }
            case .string:
                if let valueString = valueString {
                    hitch.append(UInt8.doubleQuote)
                    hitch.append(valueString)
                    hitch.append(UInt8.doubleQuote)
                } else {
                    appendNull()
                }
            case .int:
                if let valueInt = valueInt {
                    hitch.append(number: valueInt)
                } else {
                    appendNull()
                }
            case .double:
                if let valueDouble = valueDouble {
                    hitch.append(double: valueDouble)
                } else {
                    appendNull()
                }
            case .array:
                if let valueArray = valueArray {
                    hitch.append(UInt8.openBrace)
                    for idx in 0..<valueArray.count {
                        valueArray[idx].json(hitch: hitch)
                        if idx < valueArray.count - 1 {
                            hitch.append(UInt8.comma)
                        }
                    }
                    hitch.append(UInt8.closeBrace)
                } else {
                    appendNull()
                }
            case .dictionary:
                if let valueArray = valueArray,
                   let keyArray = keyArray {
                    hitch.append(UInt8.openBracket)
                    for idx in 0..<keyArray.count {
                        hitch.append(UInt8.doubleQuote)
                        hitch.append(keyArray[idx])
                        hitch.append(UInt8.doubleQuote)
                        hitch.append(UInt8.colon)
                        valueArray[idx].json(hitch: hitch)
                        if idx < keyArray.count - 1 {
                            hitch.append(UInt8.comma)
                        }
                    }
                    hitch.append(UInt8.closeBracket)
                } else {
                    appendNull()
                }
            }
            return hitch
        }

        @inlinable @inline(__always)
        public var description: String {
            return json(hitch: Hitch()).description
        }

        public let type: JsonType

        public var valueString: Hitch?
        public var valueBool: Bool?
        public var valueInt: Int?
        public var valueDouble: Double?
        public var valueArray: [JsonElement]?
        public var keyArray: [Hitch]?

        @inlinable @inline(__always)
        internal func append(value: JsonElement) {
            valueArray?.append(value)
        }

        @inlinable @inline(__always)
        internal func append(key: Hitch,
                             value: JsonElement) {
            keyArray?.append(key)
            valueArray?.append(value)
        }

        @inlinable @inline(__always)
        init() {
            type = .null

            valueString = nil
            valueBool = nil
            valueInt = nil
            valueDouble = nil
            valueArray = nil
            keyArray = nil
        }

        @inlinable @inline(__always)
        init(string: Hitch) {
            type = .string

            valueString = string
            valueBool = nil
            valueInt = nil
            valueDouble = nil
            valueArray = nil
            keyArray = nil
        }

        @inlinable @inline(__always)
        init(bool: Bool) {
            type = .boolean

            valueString = nil
            valueBool = bool
            valueInt = nil
            valueDouble = nil
            valueArray = nil
            keyArray = nil
        }

        @inlinable @inline(__always)
        init(int: Int) {
            type = .int

            valueString = nil
            valueBool = nil
            valueInt = int
            valueDouble = nil
            valueArray = nil
            keyArray = nil
        }

        @inlinable @inline(__always)
        init(double: Double) {
            type = .double

            valueString = nil
            valueBool = nil
            valueInt = nil
            valueDouble = double
            valueArray = nil
            keyArray = nil
        }

        @inlinable @inline(__always)
        init(array: [JsonElement]) {
            type = .array

            valueString = nil
            valueBool = nil
            valueInt = nil
            valueDouble = nil
            valueArray = array
            keyArray = nil
        }

        @inlinable @inline(__always)
        init(keys: [Hitch],
             values: [JsonElement]) {
            type = .dictionary

            valueString = nil
            valueBool = nil
            valueInt = nil
            valueDouble = nil
            valueArray = []
            keyArray = []
        }
    }

    @inlinable @inline(__always)
    public static func parse(hitch: Hitch) -> JsonElement? {
        let reader = Reader(hitch: hitch)

        return reader.parse()
    }

    @inlinable @inline(__always)
    public static func parse(data: Data) -> JsonElement? {
        return parse(hitch: Hitch(data: data))
    }

    @inlinable @inline(__always)
    public static func parse(string: String) -> JsonElement? {
        return parse(hitch: Hitch(stringLiteral: string))
    }

}
