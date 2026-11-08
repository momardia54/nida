import SwiftUI

/// `@State` is a macro in the macOS 27 SDK whose plugin ships only with full Xcode.
/// Using the underlying property wrapper through a typealias keeps the project buildable
/// with just the Command Line Tools. Behaves exactly like `@State`.
typealias ViewState<Value> = SwiftUI.State<Value>
