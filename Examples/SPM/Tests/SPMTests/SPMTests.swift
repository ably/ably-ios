    import XCTest
    import Ably

    final class SPMTests: XCTestCase {
        func ablyInitTest() {
            let clientOptions = ARTClientOptions()
            let _ = ARTRest(options: clientOptions)
        }
    }
