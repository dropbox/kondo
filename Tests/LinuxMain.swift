import BuckGeneratorTests
import CommandLineTests
import XCTest

var tests = [XCTestCaseEntry]()
tests += BuckGeneratorTests.allTests()
tests += CommandLineTests.allTests()
XCTMain(tests)
