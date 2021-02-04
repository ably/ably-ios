//
//  NSObject+TestSuite.swift
//  ably
//
//  Created by Ricardo Pereira on 17/02/16.
//  Copyright © 2016 Ably. All rights reserved.
//

import Aspects

extension NSObject {

    /// Inject a block of code to the identified class method.
    class func testSuite_injectIntoClassMethod(_ selector: Selector, code: @escaping ()->()) -> AspectToken? {
        let block: @convention(block) (AspectInfo) -> Void = { _ in
            code()
        }
        return try? self.aspect_hook(selector, with: AspectOptions(), usingBlock: unsafeBitCast(block, to: AnyObject.self))
    }

    /// Replace identified class method with a block of code.
    class func testSuite_replaceClassMethod(_ selector: Selector, code: @escaping ()->()) -> AspectToken? {
        let block: @convention(block) (AspectInfo) -> Void = { _ in
            code()
        }
        return try? self.aspect_hook(selector, with: .positionInstead, usingBlock: unsafeBitCast(block, to: AnyObject.self))
    }

}
