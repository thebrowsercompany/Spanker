import Foundation
import Hitch

@inlinable @inline(__always)
internal func strskip(json: HalfHitch, offset: Int, _ params: UInt8...) -> Int {
    var idx = offset
    for char in json.stride(from: offset, to: json.count) {
        guard char != 0 else { break }
        guard params.contains(char) else { break }
        idx += 1
    }
    return idx
}

@inlinable @inline(__always)
internal func strstrNoEscaped(json: HalfHitch, offset: Int, find: UInt8) -> Int {
    // look forward for the matching character, not counting escaped versions of it
    var skipNext = false
    var idx = offset
    for char in json.stride(from: offset, to: json.count) {
        guard char != 0 else { break }
        guard skipNext == false else {
            skipNext = false
            idx += 1
            continue
        }
        if char == find {
            return idx
        }
        idx += 1
    }
    return idx
}

extension Spanker {

    internal enum ValueType {
        case unknown
        case null
        case string
        case booleanTrue
        case booleanFalse
        case int
        case double
        case element
    }

    internal enum ElementType {
        case unknown
        case array
        case element
    }

    internal struct ParseValue {
        var type: ValueType = .unknown
        var nameIdx: Int = 0
        var endNameIdx: Int = 0
        var valueIdx: Int = 0

        mutating func clear() {
            self.type = .unknown
            self.nameIdx = 0
            self.valueIdx = 0
        }
    }

    @usableFromInline
    internal enum Reader {

        @usableFromInline
        internal static func parsed(hitch: Hitch, _ callback: (JsonElement?) -> Void) {
            parsed(data: hitch.dataNoCopy(), callback)
        }

        @usableFromInline
        internal static func parsed(string: String, _ callback: (JsonElement?) -> Void) {
            parsed(data: string.data(using: .utf8) ?? Data(), callback)
        }

        @usableFromInline
        internal static func parsed(data: Data, _ callback: (JsonElement?) -> Void) {
            var currentIdx = 0
            var char: UInt8 = 0

            var elementStack: [JsonElement] = []

            var jsonAttribute = ParseValue()
            var rootElement: JsonElement?
            var jsonElement: JsonElement?

            HalfHitch.using(data: data) { json in

                let parseEndElement: () -> JsonElement? = {
                    guard elementStack.count > 0 else { return nil }
                    let myElement = elementStack.removeLast()

                    if elementStack.count == 0 {
                        rootElement = myElement
                    }

                    return elementStack.last
                }

                let attributeAsHitch: (Int) -> JsonElement = { endIdx in
                    let valueString = HalfHitch(source: json, from: jsonAttribute.valueIdx, to: endIdx)
                    return JsonElement(string: valueString)
                }

                let attributeAsInt: (Int) -> JsonElement = { endIdx in
                    let valueString = HalfHitch(source: json, from: jsonAttribute.valueIdx, to: endIdx)
                    guard let value = valueString.toInt() else { return JsonElement() }
                    return JsonElement(int: value)
                }

                let attributeAsDouble: (Int) -> JsonElement = { endIdx in
                    let valueString = HalfHitch(source: json, from: jsonAttribute.valueIdx, to: endIdx)
                    guard let value = valueString.toDouble() else { return JsonElement() }
                    return JsonElement(double: value)
                }

                let attributeName: () -> HalfHitch? = {
                    guard jsonAttribute.nameIdx > 0 else { return nil }
                    guard jsonAttribute.endNameIdx > jsonAttribute.nameIdx else { return nil }
                    return HalfHitch(source: json, from: jsonAttribute.nameIdx, to: jsonAttribute.endNameIdx)
                }

                let appendElement: (HalfHitch?, JsonElement) -> Void = { key, value in
                    if let jsonElement = jsonElement {
                        if jsonElement.type == .array {
                            jsonElement.append(value: value)
                        } else if let key = key,
                                  jsonElement.type == .dictionary {
                            jsonElement.append(key: key,
                                               value: value)
                        }
                    } else {
                        rootElement = value
                        jsonElement = value
                    }
                }

                if let raw = json.raw() {

                    // find next element start
                    while true {
                        currentIdx = strskip(json: json, offset: currentIdx, .space, .tab, .newLine, .carriageReturn, .comma)
                        guard currentIdx < json.count else { break }

                        // ok, so the main algorithm is fairly simple. At this point, we've identified the start of an object enclosure,
                        // an array enclosure, or the start of a string make an element for this and put it on the stack
                        var nextCurrentIdx = currentIdx + 1

                        char = raw[currentIdx]
                        if char == .closeBracket || char == .closeBrace {
                            jsonElement = parseEndElement()
                        } else if char == .openBracket || char == .openBrace {
                            // we've found the start of a new object
                            let nextElement = (char == .openBracket) ? JsonElement(keys: [], values: []) : JsonElement(array: [])

                            elementStack.append(nextElement)

                            // if there is a parent element, we need to add this to it
                            if let jsonElement = jsonElement {
                                if let name = attributeName() {
                                    jsonElement.append(key: name, value: nextElement)
                                } else {
                                    jsonElement.append(value: nextElement)
                                }
                                jsonAttribute.clear()
                            }

                            jsonElement = nextElement

                        } else if jsonElement?.type == .dictionary && (char == .singleQuote || char == .doubleQuote) {
                            // We've found the name portion of a KVP

                            if jsonAttribute.nameIdx == 0 {
                                // Set the attribute name index
                                jsonAttribute.nameIdx = currentIdx + 1

                                // Find the name of the name string and null terminate it
                                nextCurrentIdx = strstrNoEscaped(json: json, offset: jsonAttribute.nameIdx, find: char)
                                jsonAttribute.endNameIdx = nextCurrentIdx

                                // Find the ':'
                                nextCurrentIdx = strstrNoEscaped(json: json, offset: nextCurrentIdx + 1, find: .colon) + 1

                                // skip whitespace
                                nextCurrentIdx = strskip(json: json, offset: nextCurrentIdx, .space, .tab, .newLine, .carriageReturn)

                                guard let key = attributeName() else { nextCurrentIdx += 1; continue }

                                // advance forward until we find the start of the next thing
                                var nextChar = raw[nextCurrentIdx]
                                if nextChar == .singleQuote || nextChar == .doubleQuote {
                                    // our value is a string
                                    jsonAttribute.type = .string
                                    jsonAttribute.valueIdx = nextCurrentIdx + 1

                                    nextCurrentIdx = strstrNoEscaped(json: json, offset: jsonAttribute.valueIdx, find: nextChar)

                                    appendElement(key, attributeAsHitch(nextCurrentIdx))

                                    jsonAttribute.clear()

                                    nextCurrentIdx += 1
                                } else if nextChar == .openBracket || nextChar == .openBrace {
                                    // our value is an array or an object; we will process it next time through the main loop
                                } else if nextCurrentIdx < json.count - 3 &&
                                            nextChar == .n &&
                                            raw[nextCurrentIdx+1] == .u &&
                                            raw[nextCurrentIdx+2] == .l &&
                                            raw[nextCurrentIdx+3] == .l {
                                    // our value is null; pick up at the end of it
                                    nextCurrentIdx += 4

                                    appendElement(key, JsonElement())

                                    jsonAttribute.clear()
                                } else {
                                    // our value is likely a number; capture it then advance to the next ',' or '}' or whitespace
                                    jsonAttribute.type = .int
                                    jsonAttribute.valueIdx = nextCurrentIdx

                                    while nextCurrentIdx < json.count &&
                                            nextChar != .space &&
                                            nextChar != .tab &&
                                            nextChar != .newLine &&
                                            nextChar != .carriageReturn &&
                                            nextChar != .comma &&
                                            nextChar != .closeBracket &&
                                            nextChar != .closeBrace {
                                        if nextChar == .f &&
                                            nextCurrentIdx < json.count - 4 &&
                                            raw[nextCurrentIdx+1] == .a &&
                                            raw[nextCurrentIdx+2] == .l &&
                                            raw[nextCurrentIdx+3] == .s &&
                                            raw[nextCurrentIdx+4] == .e {
                                            jsonAttribute.type = .booleanFalse
                                            nextCurrentIdx += 5
                                            break
                                        } else if nextChar == .t &&
                                            nextCurrentIdx < json.count - 3 &&
                                            raw[nextCurrentIdx+1] == .r &&
                                            raw[nextCurrentIdx+2] == .u &&
                                            raw[nextCurrentIdx+3] == .e {
                                            jsonAttribute.type = .booleanTrue
                                            nextCurrentIdx += 4
                                            break
                                        } else if nextChar == .dot {
                                            jsonAttribute.type = .double
                                        }
                                        nextCurrentIdx += 1
                                        nextChar = raw[nextCurrentIdx]
                                    }

                                    if jsonAttribute.type == .booleanTrue {
                                        appendElement(key, JsonElement(bool: true))
                                    } else if jsonAttribute.type == .booleanFalse {
                                        appendElement(key, JsonElement(bool: false))
                                    } else if jsonAttribute.type == .int {
                                        appendElement(key, attributeAsInt(nextCurrentIdx))
                                    } else if jsonAttribute.type == .double {
                                        appendElement(key, attributeAsDouble(nextCurrentIdx))
                                    }

                                    jsonAttribute.clear()

                                    if nextChar == .closeBrace {
                                        jsonElement = parseEndElement()
                                    }
                                }
                            }
                        } else {
                            nextCurrentIdx = strskip(json: json, offset: currentIdx, .space, .tab, .newLine, .carriageReturn)

                            // advance forward until we find the start of the next thing
                            var nextChar = raw[nextCurrentIdx]
                            if nextChar == .doubleQuote || nextChar == .singleQuote {
                                // our value is a string
                                jsonAttribute.type = .string
                                jsonAttribute.valueIdx = nextCurrentIdx + 1

                                nextCurrentIdx = strstrNoEscaped(json: json, offset: jsonAttribute.valueIdx, find: nextChar)

                                appendElement(nil, attributeAsHitch(nextCurrentIdx))

                                jsonAttribute.clear()

                                nextCurrentIdx += 1
                            } else if nextChar == .openBrace || nextChar == .openBracket {
                                // our value is an array or an object; we will process it next time through the main loop
                                nextCurrentIdx = nextCurrentIdx - 1
                            } else if nextCurrentIdx < json.count - 3 &&
                                        nextChar == .n &&
                                        raw[nextCurrentIdx+1] == .u &&
                                        raw[nextCurrentIdx+2] == .l &&
                                        raw[nextCurrentIdx+3] == .l {
                                // our value is null; pick up at the end of it
                                nextCurrentIdx += 4

                                appendElement(nil, JsonElement())

                                jsonAttribute.clear()
                            } else {
                                // our value is likely a number; capture it then advance to the next ',' or '}' or whitespace
                                jsonAttribute.type = .int
                                jsonAttribute.valueIdx = nextCurrentIdx

                                while nextCurrentIdx < json.count &&
                                        nextChar != .space &&
                                        nextChar != .tab &&
                                        nextChar != .newLine &&
                                        nextChar != .carriageReturn &&
                                        nextChar != .comma &&
                                        nextChar != .closeBracket &&
                                        nextChar != .closeBrace {
                                    if nextChar == .f &&
                                        nextCurrentIdx < json.count - 4 &&
                                        raw[nextCurrentIdx+1] == .a &&
                                        raw[nextCurrentIdx+2] == .l &&
                                        raw[nextCurrentIdx+3] == .s &&
                                        raw[nextCurrentIdx+4] == .e {
                                        jsonAttribute.type = .booleanFalse
                                        nextCurrentIdx += 5
                                        break
                                    } else if nextChar == .t &&
                                        nextCurrentIdx < json.count - 3 &&
                                        raw[nextCurrentIdx+1] == .r &&
                                        raw[nextCurrentIdx+2] == .u &&
                                        raw[nextCurrentIdx+3] == .e {
                                        jsonAttribute.type = .booleanTrue
                                        nextCurrentIdx += 4
                                        break
                                    } else if nextChar == .dot {
                                        jsonAttribute.type = .double
                                    }
                                    nextCurrentIdx += 1
                                    nextChar = raw[nextCurrentIdx]
                                }

                                if jsonAttribute.type == .booleanTrue {
                                    appendElement(nil, JsonElement(bool: true))
                                } else if jsonAttribute.type == .booleanFalse {
                                    appendElement(nil, JsonElement(bool: false))
                                } else if jsonAttribute.type == .int {
                                    appendElement(nil, attributeAsInt(nextCurrentIdx))
                                } else if jsonAttribute.type == .double {
                                    appendElement(nil, attributeAsDouble(nextCurrentIdx))
                                }

                                jsonAttribute.clear()

                                if nextChar == .closeBrace {
                                    jsonElement = parseEndElement()
                                }
                            }
                        }

                        currentIdx = nextCurrentIdx
                    }
                }

                while elementStack.count > 0 {
                    jsonElement = parseEndElement()
                }

                callback(rootElement)

            }

        }

    }
}
