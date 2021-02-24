//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Foundation

public struct TestFile {
  public let name: String
  public let path: String
  public let content: String

  public init(name: String, path: String, content: String) {
    self.name = name
    self.path = path
    self.content = content
  }

  public static var example1 = TestFile(
    name: "Example1.swift",
    path: "ios/app",
    content:
    """
    import Foundation
    import UIKit
    import ios_common_utilities.Swift

    public enum Example1Enum: Error {
      case first
      case second
    }

    open class Example1 {
      public struct Model: CustomStringConvertible {
        public let name: String
        public init(name: String) {
          self.name = name
        }
      }

      public init() {}

      public func process(_ utilities: Utilities, enum: Example2Enum) {

      }

    }
    """
  )

  public static var example2Header = TestFile(
    name: "Example2.h",
    path: "ios/app",
    content:
    """
    #import <Foundation/Foundation.h>
    #import <ios_common_logging/ios_common_logging-Swift.h>

    @class Example3;
    @protocol Status;

    typedef NS_ENUM(NSUInteger, Example2Enum) {
        Example2EnumUnknown,
        Example2EnumFirst,
        Example2EnumSecond,
        Example2EnumThird
    };

    extern NSString *const kExample2Extern1;
    extern NSString *const kExample2Extern2;

    @interface Example2: NSObject

    @property (nonatomic, nullable) Example3 *example3Property;
    @property (nonatomic, nullable) NSString *example2Property;
    @property (nonatomic, nullable) id<Status> example2Status;

    - (instancetype)initializeWithLogger:(Logger *)logger;

    @end
    """
  )

  public static var example2Implementation = TestFile(
    name: "Example2.m",
    path: "ios/app",
    content:
    """
    #import "Example2.h"

    #import <Foundation/Foundation.h>
    #import <ios_common_status/ios_common_status.h>
    #import "Example4Header.h"

    @implementation Example2 {
       Example4 *_example4;
    }

    - (instancetype)initializeWithLogger:(Logger *)logger { }

    - (void)printStatus {
      if (self.example2Status == nil) {
        return;
      }
    }

    @end
    """
  )

  public static var example3 = TestFile(
    name: "Example3.swift",
    path: "ios/app",
    content:
    """
    import Foundation
    import UIKit
    import ios_common_magic
    import ios_common_utilities

    public protocol Example3Delegate: class {
      func example3(_ example3: Example3, doSomeStuff: Bool)
    }

    @objc(DBExample3)
    public final class Example3: Example4 {
      public weak var delegate: Example3Delegate?
      public var utilities: Utilities? = nil

      public init() {}

      public func initialize(with magic: Magic) {

      }
    }
    """
  )

  public static var example4Header = TestFile(
    name: "Example4.h",
    path: "ios/app",
    content:
    """
    #import <Foundation/Foundation.h>
    #import <ios_common_logging/ios_common_logging.h>

    @class Example4;

    @protocol Example4Delegate <NSObject>
    - (void)doStuffFrom:(Example4 *)example4;
    @end

    @interface Example4: NSObject

    @property (nonatomic, weak) id<Example4Delegate> delegate;
    @property (nonatomic) Logger *logger;

    - (void)updateStuff:(NSString *)stuff;

    @end
    """
  )

  public static var example4Implementation = TestFile(
    name: "Example4.m",
    path: "ios/app",
    content:
    """
    #import "Example4.h"

    #import <Foundation/Foundation.h>
    #import <ios_common_utilities/ios_common_utilities.h>
    #import <ios_common_magic/ios_common_magic.h>
    #import "Example2Header.h"

    @interface Example4 ()

    @property (nonatomic) Magic *magic;

    @end

    @implementation Example4 {
      Utilities *_utilities;
    }

    - (void)updateStuff:(NSString *)stuff {
      _utilities = [[Example2 alloc] initWithStuff:stuff];
    }

    - (void)changeNumbers:(NSArray<NSNumber *>)numbers { }

    @end
    """
  )
}
