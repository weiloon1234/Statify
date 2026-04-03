import SwiftUI

extension String {
    func rightPad(to length: Int) -> String {
        if count >= length { return self }
        return self + String(repeating: " ", count: length - count)
    }
}
