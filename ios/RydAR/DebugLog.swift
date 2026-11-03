import Foundation

/// Developer diagnostics. Debug builds print to the console. Release builds write nothing,
/// so no curve id, file path, or database message reaches the device log.
@inline(__always)
func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}
