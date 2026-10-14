import Foundation
import Testing

func checkEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T) {
    do { let lhs = try a(), rhs = try b(); if lhs != rhs { Issue.record("Expected \(lhs) == \(rhs)") } }
    catch { Issue.record(error) }
}
func checkTrue(_ value: @autoclosure () throws -> Bool) {
    do { if try !value() { Issue.record("Expected true") } } catch { Issue.record(error) }
}
func checkFalse(_ value: @autoclosure () throws -> Bool) {
    do { if try value() { Issue.record("Expected false") } } catch { Issue.record(error) }
}
func checkNil<T>(_ value: @autoclosure () throws -> T?) {
    do { if try value() != nil { Issue.record("Expected nil") } } catch { Issue.record(error) }
}
func checkNotNil<T>(_ value: @autoclosure () throws -> T?) {
    do { if try value() == nil { Issue.record("Expected non-nil") } } catch { Issue.record(error) }
}
func checkThrows<T>(_ value: @autoclosure () throws -> T) {
    do { _ = try value(); Issue.record("Expected an error") } catch { }
}
