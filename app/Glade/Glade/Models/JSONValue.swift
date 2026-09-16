import Foundation

// Ordered key-value pair for preserving JSON object field order
struct JSONKeyValue: Equatable {
    let key: String
    let value: JSONValue
}

// Recursive enum representing any JSON value
indirect enum JSONValue: Equatable {
    case object([JSONKeyValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    var typeDescription: String {
        switch self {
        case .object: return "object"
        case .array: return "array"
        case .string: return "string"
        case .number: return "number"
        case .bool: return "bool"
        case .null: return "null"
        }
    }

    var displayString: String {
        switch self {
        case .object(let pairs):
            return "{\(pairs.count) keys}"
        case .array(let arr):
            return "[\(arr.count) items]"
        case .string(let s):
            return "\"\(s)\""
        case .number(let n):
            if n == n.rounded() && !n.isInfinite && abs(n) < 1e15 {
                return String(Int64(n))
            }
            return String(n)
        case .bool(let b):
            return b ? "true" : "false"
        case .null:
            return "null"
        }
    }

    var keyCount: Int {
        if case .object(let pairs) = self { return pairs.count }
        return 0
    }
}

// MARK: - Parsing from Any (JSONSerialization output)
extension JSONValue {
    static func from(_ any: Any) -> JSONValue {
        switch any {
        // NSJSONSerialization returns NSDictionary which preserves insertion order when iterated
        case let dict as NSDictionary:
            var pairs: [JSONKeyValue] = []
            for case let (key as String, value) in dict {
                pairs.append(JSONKeyValue(key: key, value: from(value)))
            }
            return .object(pairs)
        case let array as [Any]:
            return .array(array.map { from($0) })
        case let string as String:
            return .string(string)
        case let number as NSNumber:
            // Distinguish bool from number
            if number === kCFBooleanTrue as AnyObject || number === kCFBooleanFalse as AnyObject {
                return .bool(number.boolValue)
            }
            return .number(number.doubleValue)
        case is NSNull:
            return .null
        default:
            return .string(String(describing: any))
        }
    }
}
