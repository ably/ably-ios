//
//  TestUtilities.swift
//  ably
//
//  Created by Yavor Georgiev on 2.08.15.
//  Copyright © 2015 г. Ably. All rights reserved.
//

import Ably
import Foundation
import XCTest
import Quick
import Nimble
import SwiftyJSON
import SocketRocketAblyFork
import Aspects

import Ably.Private

typealias HookToken = AspectToken

let AblyTestsErrorDomain = "test.ably.io"

class CryptoTest {
    private static let aes128 = "cipher+aes-128-cbc";
    private static let aes256 = "cipher+aes-256-cbc";

    public static let fixtures: [(
        fileName: String,
        expectedEncryptedEncoding: String,
        keyLength: UInt
    )] = [
        ("crypto-data-128", aes128, 128),
        ("crypto-data-256", aes256, 256),
    ];
}

class Configuration : QuickConfiguration {
    override class func configure(_ configuration: Quick.Configuration!) {
        configuration.beforeSuite {
            AsyncDefaults.timeout = testTimeout
        }
    }
}

func pathForTestResource(_ resourcePath: String) -> String {
    let testBundle = Bundle(for: AblyTests.self)
    return testBundle.path(forResource: resourcePath, ofType: "")!
}

let appSetupJson = JSON(parseJSON: try! String(contentsOfFile: pathForTestResource(testResourcesPath + "test-app-setup.json")))

let testTimeout = DispatchTimeInterval.seconds(10)
let testResourcesPath = "ably-common/test-resources/"
let echoServerAddress = "https://echo.ably.io/createJWT"

/// Common test utilities.
class AblyTests {

    class func base64ToData(_ base64: String) -> Data {
        return Data(base64Encoded: base64, options: NSData.Base64DecodingOptions(rawValue: 0))!
    }

    class func msgpackToJSON(_ data: Data) -> JSON {
        let decoded = try! ARTMsgPackEncoder().decode(data)
        let encoded = try! ARTJsonEncoder().encode(decoded)
        return try! JSON(data: encoded)
    }

    class func checkError(_ errorInfo: ARTErrorInfo?, withAlternative message: String) {
        if let error = errorInfo {
            XCTFail("\((error ).code): \(error.message)")
        }
        else if !message.isEmpty {
            XCTFail(message)
        }
    }

    class func checkError(_ errorInfo: ARTErrorInfo?) {
        checkError(errorInfo, withAlternative: "")
    }

    class var jsonRestOptions: ARTClientOptions {
        get {
            let options = AblyTests.clientOptions()
            return options
        }
    }

    class var authTokenCases: [String: (ARTAuthOptions) -> Void] {
        get { return [
            "useTokenAuth": { $0.useTokenAuth = true; $0.key = "fake:key" },
            "authUrl": { $0.authUrl = URL(string: "http://test.com") },
            "authCallback": { $0.authCallback = { _, _ in return } },
            "tokenDetails": { $0.tokenDetails = ARTTokenDetails(token: "token") },
            "token": { $0.token = "token" },
            "key": { $0.tokenDetails = ARTTokenDetails(token: "token"); $0.key = "fake:key" }
            ]
        }
    }

    static var testApplication: JSON?
    static fileprivate var setupOptionsCounter = 0

    struct QueueIdentity {
        let label: String
    }

    static var queueIdentityKey = DispatchSpecificKey<QueueIdentity>()

    static var queue: DispatchQueue = {
        let queue = DispatchQueue(label: "io.ably.tests", qos: .userInitiated)
        queue.setSpecific(key: queueIdentityKey, value: QueueIdentity(label: queue.label))
        return queue
    }()

    static var userQueue: DispatchQueue = {
        let queue = DispatchQueue(label: "io.ably.tests.callbacks", qos: .userInitiated)
        queue.setSpecific(key: queueIdentityKey, value: QueueIdentity(label: queue.label))
        return queue
    }()
    
    static var extraQueue: DispatchQueue = {
        let queue = DispatchQueue(label: "io.ably.tests.extra", qos: .userInitiated)
        queue.setSpecific(key: queueIdentityKey, value: QueueIdentity(label: queue.label))
        return queue
    }()

    static func currentQueueLabel() -> String? {
        return DispatchQueue.getSpecific(key: queueIdentityKey)?.label
    }

    class func setupOptions(_ options: ARTClientOptions, forceNewApp: Bool = false, debug: Bool = false) -> ARTClientOptions {
        options.channelNamePrefix = "test-\(setupOptionsCounter)"
        setupOptionsCounter += 1

        if forceNewApp {
            testApplication = nil
        }

        guard let app = testApplication else {
            let request = NSMutableURLRequest(url: URL(string: "https://\(options.restHost):\(options.tlsPort)/apps")!)
            request.httpMethod = "POST"
            request.httpBody = try? appSetupJson["post_apps"].rawData()

            request.allHTTPHeaderFields = [
                "Accept" : "application/json",
                "Content-Type" : "application/json"
            ]

            let (responseData, responseError, _) = NSURLSessionServerTrustSync().get(request)

            if let error = responseError {
                fatalError(error.localizedDescription)
            }

            testApplication = try! JSON(data: responseData!)
            
            if debug {
                print(testApplication!)
            }

            return setupOptions(options, debug: debug)
        }
        
        let key = app["keys"][0]
        options.key = key["keyStr"].stringValue
        options.dispatchQueue = userQueue
        options.internalDispatchQueue = queue
        if debug {
            options.logLevel = .verbose
        }
        return options
    }
    
    class func commonAppSetup(_ debug: Bool = false) -> ARTClientOptions {
        return AblyTests.setupOptions(AblyTests.jsonRestOptions, debug: debug)
    }

    class func clientOptions(_ debug: Bool = false, key: String? = nil, requestToken: Bool = false) -> ARTClientOptions {
        let options = ARTClientOptions()
        options.environment = getEnvironment()
        options.logExceptionReportingUrl = nil
        if debug {
            options.logLevel = .debug
        }
        if let key = key {
            options.key = key
        }
        if requestToken {
            options.token = getTestToken()
        }
        options.dispatchQueue = userQueue
        options.internalDispatchQueue = queue
        return options
    }

    class func newErrorProtocolMessage(message: String = "Fail test") -> ARTProtocolMessage {
        let protocolMessage = ARTProtocolMessage()
        protocolMessage.action = .error
        protocolMessage.error = ARTErrorInfo.create(withCode: 0, message: message)
        return protocolMessage
    }

    class func newPresenceProtocolMessage(_ channel: String, action: ARTPresenceAction, clientId: String) -> ARTProtocolMessage {
        let protocolMessage = ARTProtocolMessage()
        protocolMessage.action = .presence
        protocolMessage.channel = channel
        protocolMessage.timestamp = Date()
        let presenceMessage = ARTPresenceMessage()
        presenceMessage.action = action
        presenceMessage.clientId = clientId
        presenceMessage.timestamp = Date()
        protocolMessage.presence = [presenceMessage]
        return protocolMessage
    }

    class func newRealtime(_ options: ARTClientOptions) -> ARTRealtime {
        let autoConnect = options.autoConnect
        options.autoConnect = false
        let realtime = ARTRealtime(options: options)
        realtime.internal.setTransport(TestProxyTransport.self)
        realtime.internal.setReachabilityClass(TestReachability.self)
        if autoConnect {
            options.autoConnect = true
            realtime.connect()
        }
        return realtime
    }

    class func newRandomString() -> String {
        return ProcessInfo.processInfo.globallyUniqueString
    }

    class func addMembersSequentiallyToChannel(_ channelName: String, members: Int = 1, startFrom: Int = 1, data: AnyObject? = nil, options: ARTClientOptions, done: @escaping ()->()) -> ARTRealtime {
        let client = ARTRealtime(options: options)
        let channel = client.channels.get(channelName)

        class Total {
            static var count: Int = 0
        }

        Total.count = 0
        channel.attach() { _ in
            for i in startFrom..<startFrom+members {
                channel.presence.enterClient("user\(i)", data: data) { _ in
                    Total.count += 1
                    if Total.count == members {
                        done()
                    }
                }
            }
        }

        return client
    }

    class func splitDone(_ howMany: Int, file: StaticString = #file, line: UInt = #line, done: @escaping () -> Void) -> (() -> Void) {
        var left = howMany
        return {
            left -= 1
            if left == 0 {
                done()
            } else if left < 0 {
                XCTFail("splitDone called more than the expected \(howMany) times", file: file, line: line)
            }
        }
    }

    class func waitFor<T>(timeout: DispatchTimeInterval, file: FileString = #file, line: UInt = #line, f: @escaping (@escaping (T?) -> Void) -> Void) -> T? {
        var value: T?
        waitUntil(timeout: timeout, file: file, line: line) { done in
            f() { v in
                value = v
                done()
            }
        }
        return value
    }

    class func wait(for expectations: [XCTestExpectation], timeout dispatchInterval: DispatchTimeInterval = testTimeout, file: Nimble.FileString = #file, line: UInt = #line) {
        let result = XCTWaiter.wait(
            for: expectations,
            timeout: dispatchInterval.toTimeInterval(),
            enforceOrder: true
        )

        let title: String = "Waiter of expectations \(expectations.map({ $0.description }))"
        switch result {
        case .timedOut:
            fail(title + " timed out (\(dispatchInterval)).", file: file, line: line)
        case .invertedFulfillment:
            fail(title + " shouldn't receive a fulfillment.", file: file, line: line)
        case .interrupted:
            fail(title + " got interrupted.", file: file, line: line)
        case .incorrectOrder:
            fail(title + " failed with incorrect order.", file: file, line: line)
        case .completed:
            break //completed successfully
        default:
            preconditionFailure("XCTWaiter.Result.\(String(describing: result)) not implemented")
        }
    }

    // MARK: Crypto

    struct CryptoTestItem {

        struct TestMessage {
            let name: String
            let data: String
            let encoding: String
        }

        let encoded: TestMessage
        let encrypted: TestMessage

        init(object: JSON) {
            let encodedJson = object["encoded"]
            encoded = TestMessage(name: encodedJson["name"].stringValue, data: encodedJson["data"].stringValue, encoding: encodedJson["encoding"].string ?? "")
            let encryptedJson = object["encrypted"]
            encrypted = TestMessage(name: encryptedJson["name"].stringValue, data: encryptedJson["data"].stringValue, encoding: encryptedJson["encoding"].stringValue)
        }

    }

    class func loadCryptoTestData(_ fileName: String) -> (key: Data, iv: Data, items: [CryptoTestItem]) {
        let file = testResourcesPath + fileName + ".json";
        let json = JSON(parseJSON: try! String(contentsOfFile: pathForTestResource(file)))

        let keyData = Data(base64Encoded: json["key"].stringValue, options: Data.Base64DecodingOptions(rawValue: 0))!
        let ivData = Data(base64Encoded: json["iv"].stringValue, options: Data.Base64DecodingOptions(rawValue: 0))!
        let items = json["items"].map{ $0.1 }.map(CryptoTestItem.init)
        
        return (keyData, ivData, items)
    }
}

class NSURLSessionServerTrustSync: NSObject, URLSessionDelegate, URLSessionTaskDelegate {

    func get(_ request: NSMutableURLRequest) -> (Data?, NSError?, HTTPURLResponse?) {
        var responseError: NSError?
        var responseData: Data?
        var httpResponse: HTTPURLResponse?;
        var requestCompleted = false

        let configuration = URLSessionConfiguration.default
        let queue = OperationQueue()
        queue.underlyingQueue = AblyTests.extraQueue
        let session = Foundation.URLSession(configuration:configuration, delegate:self, delegateQueue:queue)

        let task = session.dataTask(with: request as URLRequest, completionHandler: { data, response, error in
            if let response = response as? HTTPURLResponse {
                responseData = data
                responseError = error as NSError?
                httpResponse = response
            }
            else if let error = error {
                responseError = error as NSError?
            }
            requestCompleted = true
        }) 
        task.resume()

        while !requestCompleted {
            CFRunLoopRunInMode(CFRunLoopMode.defaultMode, CFTimeInterval(0.1), Bool(truncating: 0))
        }

        return (responseData, responseError, httpResponse)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Try to extract the server certificate for trust validation
        if let serverTrust = challenge.protectionSpace.serverTrust {
            // Server trust authentication
            // Reference: https://developer.apple.com/library/ios/documentation/Cocoa/Conceptual/URLLoadingSystem/Articles/AuthenticationChallenges.html
            completionHandler(Foundation.URLSession.AuthChallengeDisposition.useCredential, URLCredential(trust: serverTrust))
        }
        else {
            challenge.sender?.performDefaultHandling?(for: challenge)
            XCTFail("Current authentication: \(challenge.protectionSpace.authenticationMethod)")
        }
    }

}

extension Date {
    func isBefore(_ other: Date) -> Bool {
        return self.compare(other) == ComparisonResult.orderedAscending
    }
}

// MARK: ARTAuthOptions Equatable

func ==(lhs: ARTAuthOptions, rhs: ARTAuthOptions) -> Bool {
    return lhs.token == rhs.token &&
        lhs.authMethod == rhs.authMethod &&
        lhs.authUrl == rhs.authUrl &&
        lhs.key == rhs.key
}

func ==(lhs: ARTJsonCompatible?, rhs: ARTJsonCompatible?) -> Bool {
    guard let lhs = lhs else {
        return rhs == nil
    }
    guard let rhs = rhs else {
        return false
    }
    do {
        return NSDictionary(dictionary: try lhs.toJSON()).isEqual(to: try rhs.toJSON())
    } catch {
        return false
    }
}

// MARK: Publish message class

class PublishTestMessage {

    var completion: ((ARTErrorInfo?) -> Void)? = nil
    var error: ARTErrorInfo? = nil

    init(client: ARTRest, failOnError: Bool = true, completion: ((ARTErrorInfo?) -> Void)? = nil) {
        client.channels.get("test").publish(nil, data: "message") { error in
            self.error = error
            if let callback = completion {
                callback(error)
            }
            else if failOnError, let e = error {
                XCTFail("Got error '\(e)'")
            }
        }
    }

    init(client: ARTRealtime, failOnError: Bool = true, completion: ((ARTErrorInfo?) -> Void)? = nil) {
        let complete: (ARTErrorInfo?) -> Void = { errorInfo in
            // ARTErrorInfo to NSError
            self.error = errorInfo

            if let callback = completion {
                callback(self.error)
            }
            else if failOnError, let e = self.error {
                XCTFail("Got error '\(e)'")
            }
        }

        client.connection.on { stateChange in
            let stateChange = stateChange!
            let state = stateChange.current
            if state == .connected {
                let channel = client.channels.get("test")
                channel.on { stateChange in
                    switch stateChange!.current {
                    case .attached:
                        channel.publish(nil, data: "message") { errorInfo in
                            complete(errorInfo)
                        }
                    case .failed:
                        complete(stateChange!.reason)
                    default:
                        break
                    }
                }
                channel.attach()
            }
        }
    }

}

/// Rest - Publish message
@discardableResult func publishTestMessage(_ rest: ARTRest, completion: Optional<(ARTErrorInfo?)->()>) -> PublishTestMessage {
    return PublishTestMessage(client: rest, failOnError: false, completion: completion)
}

@discardableResult func publishTestMessage(_ rest: ARTRest, failOnError: Bool = true) -> PublishTestMessage {
    return PublishTestMessage(client: rest, failOnError: failOnError)
}

/// Realtime - Publish message with callback
/// (publishes if connection state changes to CONNECTED and channel state changes to ATTACHED)
@discardableResult func publishFirstTestMessage(_ realtime: ARTRealtime, completion: Optional<(ARTErrorInfo?)->()>) -> PublishTestMessage {
    return PublishTestMessage(client: realtime, failOnError: false, completion: completion)
}

/// Realtime - Publish message
/// (publishes if connection state changes to CONNECTED and channel state changes to ATTACHED)
@discardableResult func publishFirstTestMessage(_ realtime: ARTRealtime, failOnError: Bool = true) -> PublishTestMessage {
    return PublishTestMessage(client: realtime, failOnError: failOnError)
}

/// Access Token
func getTestToken(key: String? = nil, clientId: String? = nil, capability: String? = nil, ttl: TimeInterval? = nil, file: FileString = #file, line: UInt = #line) -> String {
    return getTestTokenDetails(key: key, clientId: clientId, capability: capability, ttl: ttl, file: file, line: line)?.token ?? ""
}

func getTestToken(key: String? = nil, clientId: String? = nil, capability: String? = nil, ttl: TimeInterval? = nil, file: FileString = #file, line: UInt = #line, completion: @escaping (String) -> Void) {
    getTestTokenDetails(key: key, clientId: clientId, capability: capability, ttl: ttl) { tokenDetails, error in
        if let e = error {
            fail(e.localizedDescription, file: file, line: line)
        }
        completion(tokenDetails?.token ?? "")
    }
}

/// Access TokenDetails
func getTestTokenDetails(key: String? = nil, clientId: String? = nil, capability: String? = nil, ttl: TimeInterval? = nil, queryTime: Bool? = nil, completion: @escaping (ARTTokenDetails?, Error?) -> Void) {
    let options: ARTClientOptions
    if let key = key {
        options = AblyTests.clientOptions()
        options.key = key
    }
    else {
        options = AblyTests.commonAppSetup()
    }
    if let queryTime = queryTime {
        options.queryTime = queryTime
    }

    let client = ARTRest(options: options)

    var tokenParams: ARTTokenParams? = nil
    if let capability = capability {
        tokenParams = ARTTokenParams()
        tokenParams!.capability = capability
    }
    if let ttl = ttl {
        if tokenParams == nil { tokenParams = ARTTokenParams() }
        tokenParams!.ttl = NSNumber(value: ttl)
    }
    if let clientId = clientId {
        if tokenParams == nil { tokenParams = ARTTokenParams() }
        tokenParams!.clientId = clientId
    }

    client.auth.requestToken(tokenParams, with: nil) { details, error in
        _ = client // Hold reference to client, since requestToken is async and will lose it.
        completion(details, error)
    }
}

func getTestTokenDetails(key: String? = nil, clientId: String? = nil, capability: String? = nil, ttl: TimeInterval? = nil, queryTime: Bool? = nil, file: FileString = #file, line: UInt = #line) -> ARTTokenDetails? {
    guard let (tokenDetails, error) = (AblyTests.waitFor(timeout: testTimeout, file: file, line: line) { value in
        getTestTokenDetails(key: key, clientId: clientId, capability: capability, ttl: ttl, queryTime: queryTime) { tokenDetails, error in
            value((tokenDetails, error))
        }
    }) else {
        return nil
    }

    if let e = error {
        fail(e.localizedDescription, file: file, line: line)
    }
    return tokenDetails
}

func getJWTToken(invalid: Bool = false, expiresIn: Int = 3600, clientId: String = "testClientIDiOS", capability: String = "{\"*\":[\"*\"]}", jwtType: String = "", encrypted: Int = 0) -> String? {
    let options = AblyTests.commonAppSetup()
    guard let components = options.key?.components(separatedBy: ":"), let keyName = components.first, var keySecret = components.last else {
        fail("Invalid API key: \(options.key ?? "nil")")
        return nil
    }
    if (invalid) {
        keySecret = "invalid"
    }

    var urlComponents = URLComponents(string: echoServerAddress)
    urlComponents?.queryItems = [
        URLQueryItem(name: "keyName", value: keyName),
        URLQueryItem(name: "keySecret", value: keySecret),
        URLQueryItem(name: "expiresIn", value: String(expiresIn)),
        URLQueryItem(name: "clientId", value: clientId),
        URLQueryItem(name: "capability", value: capability),
        URLQueryItem(name: "jwtType", value: jwtType),
        URLQueryItem(name: "encrypted", value: String(encrypted)),
        URLQueryItem(name: "environment", value: getEnvironment()) 
    ]
    
    let request = NSMutableURLRequest(url: urlComponents!.url!)
    let (responseData, responseError, _) = NSURLSessionServerTrustSync().get(request)
    if let error = responseError {
        fail(error.localizedDescription)
        return nil
    }
    return String(data: responseData!, encoding: String.Encoding.utf8)
}

func getKeys() -> Dictionary<String, String> {
    let options = AblyTests.commonAppSetup()
    guard let components = options.key?.components(separatedBy: ":"), let keyName = components.first, let keySecret = components.last else {
        fatalError("Invalid API key)")
    }
    return ["keyName": keyName, "keySecret": keySecret]
}

public func delay(_ seconds: TimeInterval, closure: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: closure)
}

public func getEnvironment() -> String {
    let b = Bundle(for: AblyTests.self)    
    guard let env = b.infoDictionary!["ABLY_ENV"] as? String, env.count > 0 else {
        return "sandbox"
    }
    return env
}

public func buildMessagesThatExceedMaxMessageSize() -> [ARTMessage] {
    var messages = [ARTMessage]()
    for index in 0...5000 {
        let m = ARTMessage(name: "name-\(index)", data: "data-\(index)")
        messages.append(m)
    }
    return messages
}

public func buildStringThatExceedMaxMessageSize() -> String {
    var name = ""
    for index in 0...10000 {
        name += "name-\(index)"
    }
    return name
}

class Box<T> {
    let unbox: T
    init(_ value: T) {
        self.unbox = value
    }
}

enum Result<T> {
    case success(Box<T>)
    case failure(String)
    /// Constructs a success wrapping a `value`.
    init(value: Box<T>) {
        self = .success(value)
    }
    /// Constructs a failure wrapping an `error`.
    init(error: String) {
        self = .failure(error)
    }
}

func extractURL(_ request: URLRequest?) -> Result<URL> {
    guard let request = request
        else { return Result(error: "No request found") }
    
    guard let url = request.url
        else { return Result(error: "Request has no URL defined") }
    
    return Result.success(Box(url))
}

func extractBodyAsJSON(_ request: URLRequest?) -> Result<NSDictionary> {
    guard let request = request
        else { return Result(error: "No request found") }
    
    guard let bodyData = request.httpBody
        else { return Result(error: "No HTTPBody") }
    
    guard let json = try? JSONSerialization.jsonObject(with: bodyData, options: .mutableLeaves)
        else { return Result(error: "Invalid json") }
    
    guard let httpBody = json as? NSDictionary
        else { return Result(error: "HTTPBody has invalid format") }

    return Result.success(Box(httpBody))
}

func extractBodyAsMsgPack(_ request: URLRequest?) -> Result<NSDictionary> {
    guard let request = request
        else { return Result(error: "No request found") }

    guard let bodyData = request.httpBody
        else { return Result(error: "No HTTPBody") }

    let json = try! ARTMsgPackEncoder().decode(bodyData)

    guard let httpBody = json as? NSDictionary
        else { return Result(error: "expected dictionary, got \(type(of: (json) as AnyObject)): \(json)") }

    return Result.success(Box(httpBody))
}

func extractBodyAsMessages(_ request: URLRequest?) -> Result<[NSDictionary]> {
    guard let request = request
        else { return Result(error: "No request found") }

    guard let bodyData = request.httpBody
        else { return Result(error: "No HTTPBody") }

    let json = try! ARTMsgPackEncoder().decode(bodyData)

    guard let httpBody = json as? NSArray
        else { return Result(error: "expected array, got \(type(of: (json) as AnyObject)): \(json)") }

    return Result.success(Box(httpBody.map{$0 as! NSDictionary}))
}

func extractURLQueryValue(_ url: URL?, key name: String) -> String? {
    guard let query = url?.query else {
        return nil
    }
    let queryItems = query.components(separatedBy: "&")
    for item in queryItems {
        let param = item.components(separatedBy: "=")
        if param.first == name {
            return param.last
        }
    }
    return nil
}

enum FakeNetworkResponse {
    case noInternet
    case hostUnreachable
    case requestTimeout(timeout: TimeInterval)
    case hostInternalError(code: Int)
    case host400BadRequest

    var error: NSError {
        switch self {
        case .noInternet:
            return NSError(domain: NSPOSIXErrorDomain, code: 50, userInfo: [NSLocalizedDescriptionKey: "network is down", NSLocalizedFailureReasonErrorKey: AblyTestsErrorDomain + ".FakeNetworkResponse"])
        case .hostUnreachable:
            return NSError(domain: kCFErrorDomainCFNetwork as String, code: 2, userInfo: [NSLocalizedDescriptionKey: "host unreachable", NSLocalizedFailureReasonErrorKey: AblyTestsErrorDomain + ".FakeNetworkResponse"])
        case .requestTimeout:
            return NSError(domain: "com.squareup.SocketRocket", code: 504, userInfo: [NSLocalizedDescriptionKey: "timed out", NSLocalizedFailureReasonErrorKey: AblyTestsErrorDomain + ".FakeNetworkResponse"])
        case .hostInternalError(let code):
            return NSError(domain: AblyTestsErrorDomain, code: code, userInfo: [NSLocalizedDescriptionKey: "internal error", NSLocalizedFailureReasonErrorKey: AblyTestsErrorDomain + ".FakeNetworkResponse"])
        case .host400BadRequest:
            return NSError(domain: AblyTestsErrorDomain, code: 400, userInfo: [NSLocalizedDescriptionKey: "bad request", NSLocalizedFailureReasonErrorKey: AblyTestsErrorDomain + ".FakeNetworkResponse"])
        }
    }

    func transportError(for url: URL) -> ARTRealtimeTransportError {
        switch self {
        case .noInternet:
            return ARTRealtimeTransportError(error: error, type: .noInternet, url: url)
        case .hostUnreachable:
            return ARTRealtimeTransportError(error: error, type: .hostUnreachable, url: url)
        case .requestTimeout:
            return ARTRealtimeTransportError(error: error, type: .timeout, url: url)
        case .hostInternalError(let code):
            return ARTRealtimeTransportError(error: error, badResponseCode: code, url: url)
        case .host400BadRequest:
            return ARTRealtimeTransportError(error: error, badResponseCode: 400, url: url)
        }
    }
}

class MockHTTP: ARTHttp {

    let network: FakeNetworkResponse

    init(network: FakeNetworkResponse, logger: ARTLog) {
        self.network = network
        super.init(AblyTests.queue, logger: logger)
    }

    override public func execute(_ request: URLRequest, completion callback: ((HTTPURLResponse?, Data?, Error?) -> Void)? = nil) -> (ARTCancellable & NSObjectProtocol)? {
        AblyTests.queue.async { // Delay to simulate asynchronicity.
            switch self.network {
            case .noInternet:
                callback?(nil, nil, NSError(domain: NSURLErrorDomain, code: -1009, userInfo: [NSLocalizedDescriptionKey: "The Internet connection appears to be offline."]))
            case .hostUnreachable:
                callback?(nil, nil, NSError(domain: NSURLErrorDomain, code: -1003, userInfo: [NSLocalizedDescriptionKey: "A server with the specified hostname could not be found."]))
            case .requestTimeout(let timeout):
                delay(timeout) {
                    callback?(nil, nil, NSError(domain: NSURLErrorDomain, code: -1001, userInfo: [NSLocalizedDescriptionKey: "The request timed out."]))
                }
            case .hostInternalError(let code):
                callback?(HTTPURLResponse(url: URL(string: "http://ios.test.suite")!, statusCode: code, httpVersion: nil, headerFields: nil), nil, nil)
            case .host400BadRequest:
                callback?(HTTPURLResponse(url: URL(string: "http://ios.test.suite")!, statusCode: 400, httpVersion: nil, headerFields: nil), nil, nil)
            }
        }
        return nil
    }

}

struct ErrorSimulator {
    let value: Int
    let description: String
    let serverId = "server-test-suite"
    var statusCode: Int = 401
    var shouldPerformRequest: Bool = false

    mutating func stubResponse(_ url: URL) -> HTTPURLResponse? {
        return HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Length": String(stubData?.count ?? 0),
            "Content-Type": "application/json",
            "X-Ably-Errorcode": String(value),
            "X-Ably-Errormessage": description,
            "X-Ably-Serverid": serverId,
            ]
        )
    }

    lazy var stubData: Data? = {
        let jsonObject = ["error": [
            "statusCode": modf(Float(self.value)/100).0, //whole number part
            "code": self.value,
            "message": self.description,
            "serverId": self.serverId,
            ]
        ]
        return try? JSONSerialization.data(withJSONObject: jsonObject, options: JSONSerialization.WritingOptions.init(rawValue: 0))
    }()
}

class MockHTTPExecutor: NSObject, ARTHTTPAuthenticatedExecutor {

    fileprivate var errorSimulator: NSError?

    var _logger = ARTLog()
    var clientOptions = ARTClientOptions()
    var encoder = ARTJsonLikeEncoder()
    var requests: [URLRequest] = []

    func logger() -> ARTLog {
        return _logger
    }

    func options() -> ARTClientOptions {
        return self.clientOptions
    }

    func defaultEncoder() -> ARTEncoder {
        return self.encoder
    }

    func execute(_ request: NSMutableURLRequest, withAuthOption authOption: ARTAuthentication, completion callback: @escaping (HTTPURLResponse?, Data?, Error?) -> Void) -> (ARTCancellable & NSObjectProtocol)? {
        self.requests.append(request as URLRequest)

        if let simulatedError = errorSimulator, var _ = request.url {
            defer { errorSimulator = nil }
            callback(nil, nil, simulatedError)
            return nil
        }

        callback(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["X-Ably-HTTPExecutor": "MockHTTPExecutor"]), nil, nil)
        return nil
    }

    func execute(_ request: URLRequest, completion callback: ((HTTPURLResponse?, Data?, Error?) -> Void)? = nil) -> (ARTCancellable & NSObjectProtocol)? {
        self.requests.append(request)
        
        if let simulatedError = errorSimulator, var _ = request.url {
            defer { errorSimulator = nil }
            callback?(nil, nil, simulatedError)
            return nil
        }

        callback?(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["X-Ably-HTTPExecutor": "MockHTTPExecutor"]), nil, nil)
        return nil
    }

    func simulateIncomingErrorOnNextRequest(_ error: NSError) {
        errorSimulator = error
    }

    func reset() {
        requests.removeAll()
    }

}

/// Records each request and response for test purpose.
class TestProxyHTTPExecutor: NSObject, ARTHTTPExecutor {

    fileprivate var errorSimulator: ErrorSimulator?

    var http: ARTHttp!
    var _logger: ARTLog!
    
    init(_ logger: ARTLog) {
        self._logger = logger
        self.http = ARTHttp(AblyTests.queue, logger: _logger)
    }
    
    func logger() -> ARTLog {
        return self._logger
    }

    var requests: [URLRequest] = []
    var responses: [HTTPURLResponse] = []

    var beforeRequest: ((URLRequest, ((HTTPURLResponse?, Data?, NSError?) -> Void)?) -> Void)?
    var afterRequest: ((URLRequest, ((HTTPURLResponse?, Data?, NSError?) -> Void)?) -> Void)?
    var beforeProcessingDataResponse: ((Data?) -> (Data))?

    public func execute(_ request: URLRequest, completion callback: ((HTTPURLResponse?, Data?, Error?) -> Void)? = nil) -> (ARTCancellable & NSObjectProtocol)? {
        guard let http = self.http else {
            return nil
        }
        self.requests.append(request)

        if let performEvent = beforeRequest {
           performEvent(request, callback)
       }

        if var simulatedError = errorSimulator, let requestURL = request.url {
            defer {
                errorSimulator = nil
            }
            if simulatedError.shouldPerformRequest {
                return http.execute(request, completion: { response, data, error in
                    callback?(simulatedError.stubResponse(requestURL), simulatedError.stubData, nil)
                })
            }
            else {
                callback?(simulatedError.stubResponse(requestURL), simulatedError.stubData, nil)
                return nil
            }            
        }

        let task = http.execute(request, completion: { response, data, error in
            if let httpResponse = response {
                self.responses.append(httpResponse)
            }
            if let performEvent = self.beforeProcessingDataResponse {
                callback?(response, performEvent(data), error as NSError?)
            }
            else {
                callback?(response, data, error as NSError?)
            }
        })
        if let performEvent = afterRequest {
            performEvent(request, callback)
        }
        return task
    }

    func simulateIncomingServerErrorOnNextRequest(_ errorValue: Int, description: String) {
        errorSimulator = ErrorSimulator(value: errorValue, description: description, statusCode: 401, shouldPerformRequest: false, stubData: nil)
    }

    func simulateIncomingServerErrorOnNextRequest(_ error: ErrorSimulator) {
        errorSimulator = error
    }

    func simulateIncomingPayloadOnNextRequest(_ data: Data) {
        errorSimulator = ErrorSimulator(value: 0, description: "", statusCode: 200, shouldPerformRequest: false, stubData: data)
    }

}

/// Records each message for test purpose.
class TestProxyTransport: ARTWebSocketTransport {

    var lastUrl: URL?

    fileprivate(set) var protocolMessagesSent = [ARTProtocolMessage]()
    fileprivate(set) var protocolMessagesReceived = [ARTProtocolMessage]()
    fileprivate(set) var protocolMessagesSentIgnored = [ARTProtocolMessage]()

    fileprivate(set) var rawDataSent = [Data]()
    fileprivate(set) var rawDataReceived = [Data]()
    fileprivate var replacingAcksWithNacks: ARTErrorInfo?

    var ignoreWebSocket = false

    var beforeProcessingSentMessage: ((ARTProtocolMessage) -> Void)?
    var beforeProcessingReceivedMessage: ((ARTProtocolMessage) -> Void)?
    var afterProcessingReceivedMessage: ((ARTProtocolMessage) -> Void)?
    var changeReceivedMessage: ((ARTProtocolMessage) -> ARTProtocolMessage)?

    var actionsIgnored = [ARTProtocolMessageAction]()
    var ignoreSends = false

    /// This will affect all WebSocketTransport instances.
    /// Set it to nil after the test ends.
    static var fakeNetworkResponse: FakeNetworkResponse?
    static var networkConnectEvent: ((ARTRealtimeTransport, URL) -> Void)?

    override func connect(withKey key: String) {
        if let fakeResponse = TestProxyTransport.fakeNetworkResponse {
            setupFakeNetworkResponse(fakeResponse)
        }
        super.connect(withKey: key)
        performNetworkConnectEvent()
    }

    override func connect(withToken token: String) {
        if let fakeResponse = TestProxyTransport.fakeNetworkResponse {
            setupFakeNetworkResponse(fakeResponse)
        }
        super.connect(withToken: token)
        performNetworkConnectEvent()
    }

    private func setupFakeNetworkResponse(_ networkResponse: FakeNetworkResponse) {
        var hook: AspectToken?
        hook = ARTSRWebSocket.testSuite_replaceClassMethod(#selector(ARTSRWebSocket.open)) {
            if TestProxyTransport.fakeNetworkResponse == nil {
                return
            }

            func performFakeConnectionError(_ secondsForDelay: TimeInterval, error: ARTRealtimeTransportError) {
                AblyTests.queue.asyncAfter(deadline: .now() + secondsForDelay) {
                    self.delegate?.realtimeTransportFailed(self, withError: error)
                    hook?.remove()
                }
            }

            guard let url = self.lastUrl else {
                fatalError("MockNetworkResponse: lastUrl should not be nil")
            }

            switch networkResponse {
            case .noInternet,
                 .hostUnreachable,
                 .hostInternalError,
                 .host400BadRequest:
                performFakeConnectionError(0.1, error: networkResponse.transportError(for: url))
            case .requestTimeout(let timeout):
                performFakeConnectionError(0.1 + timeout, error: networkResponse.transportError(for: url))
            }
        }
    }

    private func performNetworkConnectEvent() {
        guard let networkConnectEventHandler = TestProxyTransport.networkConnectEvent else {
            return
        }
        if let lastUrl = self.lastUrl {
            networkConnectEventHandler(self, lastUrl)
        }
        else {
            AblyTests.queue.asyncAfter(deadline: .now() + 0.1) {
                // Repeat until `lastUrl` is assigned.
                self.performNetworkConnectEvent()
            }
        }
    }

    override func setupWebSocket(_ params: [URLQueryItem], with options: ARTClientOptions, resumeKey: String?, connectionSerial: NSNumber?) -> URL {
        let url = super.setupWebSocket(params, with: options, resumeKey: resumeKey, connectionSerial: connectionSerial)
        lastUrl = url
        return url
    }

    func send(_ message: ARTProtocolMessage) {
        let data = try! encoder.encode(message)
        send(data, withSource: message)
    }

    @discardableResult
    override func send(_ data: Data, withSource decodedObject: Any?) -> Bool {
        if let networkAnswer = TestProxyTransport.fakeNetworkResponse, let ws = self.websocket {
            // Ignore it because it should fake a failure.
            self.webSocket(ws, didFailWithError: networkAnswer.error)
            return false
        }

        if let msg = decodedObject as? ARTProtocolMessage {
            if ignoreSends {
                protocolMessagesSentIgnored.append(msg)
                return false
            }
            protocolMessagesSent.append(msg)
            if let performEvent = beforeProcessingSentMessage {
                performEvent(msg)
            }
        }
        rawDataSent.append(data)
        return super.send(data, withSource: decodedObject)
    }

    override func receive(_ original: ARTProtocolMessage) {
        if original.action == .ack || original.action == .presence {
            if let error = replacingAcksWithNacks {
                original.action = .nack
                original.error = error
            }
        }
        protocolMessagesReceived.append(original)
        if actionsIgnored.contains(original.action) {
            return
        }
        if let performEvent = beforeProcessingReceivedMessage {
            performEvent(original)
        }
        var msg = original
        if let performEvent = changeReceivedMessage {
            msg = performEvent(original)
        }
        super.receive(msg)
        if let performEvent = afterProcessingReceivedMessage {
            performEvent(original)
        }
    }

    override func receive(with data: Data) -> ARTProtocolMessage? {
        rawDataReceived.append(data)
        return super.receive(with: data)
    }

    func replaceAcksWithNacks(_ error: ARTErrorInfo, block: (_ doneReplacing: @escaping () -> Void) -> Void) {
        replacingAcksWithNacks = error
        block({ self.replacingAcksWithNacks = nil })
    }

    func simulateTransportSuccess(clientId: String? = nil) {
        self.ignoreWebSocket = true
        let msg = ARTProtocolMessage()
        msg.action = .connected
        msg.connectionId = "x-xxxxxxxx"
        msg.connectionKey = "xxxxxxx-xxxxxxxxxxxxxx-xxxxxxxx"
        msg.connectionSerial = -1
        msg.connectionDetails = ARTConnectionDetails(clientId: clientId, connectionKey: "a8c10!t-3D0O4ejwTdvLkl-b33a8c10", maxMessageSize: 16384, maxFrameSize: 262144, maxInboundRate: 250, connectionStateTtl: 60, serverId: "testServerId", maxIdleInterval: 15000)
        super.receive(msg)
    }

    override func webSocketDidOpen(_ webSocket: ARTWebSocket) {
        if !ignoreWebSocket {
            super.webSocketDidOpen(webSocket)
        }
    }

    override func webSocket(_ webSocket: ARTWebSocket, didFailWithError error: Error) {
        if !ignoreWebSocket {
            super.webSocket(webSocket, didFailWithError: error)
        }
    }

    override func webSocket(_ webSocket: ARTWebSocket, didReceiveMessage message: Any?) {
        if let networkAnswer = TestProxyTransport.fakeNetworkResponse, let ws = self.websocket {
            // Ignore it because it should fake a failure.
            self.webSocket(ws, didFailWithError: networkAnswer.error)
            return
        }

        if !ignoreWebSocket {
            super.webSocket(webSocket, didReceiveMessage: message as Any)
        }
    }

    override func webSocket(_ webSocket: ARTWebSocket, didCloseWithCode code: Int, reason: String?, wasClean: Bool) {
        if !ignoreWebSocket {
            super.webSocket(webSocket, didCloseWithCode: code, reason: reason, wasClean: wasClean)
        }
    }
}


// MARK: - Extensions

extension Sequence where Iterator.Element == Data {

    func toMsgPackArray<T>() -> [T] {
        let msgPackEncoder = ARTMsgPackEncoder()
        return map({ try! msgPackEncoder.decode($0) as! T })
    }
    
}

func + <K,V> (left: Dictionary<K,V>, right: Dictionary<K,V>?) -> Dictionary<K,V> {
    guard let right = right else { return left }
    return left.reduce(right) {
        var new = $0 as [K:V]
        new.updateValue($1.1, forKey: $1.0)
        return new
    }
}

func += <K,V> (left: inout Dictionary<K,V>, right: Dictionary<K,V>?) {
    guard let right = right else { return }
    right.forEach { key, value in
        left.updateValue(value, forKey: key)
    }
}

extension Collection {

    /// Returns the element at the specified index iff it is within bounds, otherwise nil.
    public func at(_ i: Index) -> Iterator.Element? {
        return (i >= startIndex && i < endIndex) ? self[i] : nil
    }

}

extension Dictionary {

    /// Returns the element at the specified index iff it is within bounds, otherwise nil.
    public func at(_ key: Key) -> Iterator.Element? {
        guard let index = index(forKey: key) else {
            return nil
        }
        return at(index)
    }

}

extension ARTMessage {

    open override func isEqual(_ object: Any?) -> Bool {
        if let other = object as? ARTMessage {
            return self.name == other.name &&
                self.encoding == other.encoding &&
                self.data as! NSObject == other.data as! NSObject
        }

        return super.isEqual(object)
    }

}

extension NSObject {

    var toBase64: String {
        return (try? JSONSerialization.data(withJSONObject: self, options: JSONSerialization.WritingOptions(rawValue: 0)).base64EncodedString(options: NSData.Base64EncodingOptions(rawValue: 0))) ?? ""
    }

}

extension Data {

    var toBase64: String {
        return self.base64EncodedString(options: NSData.Base64EncodingOptions(rawValue: 0))
    }

    var toUTF8String: String {
        return NSString(data: self, encoding: String.Encoding.utf8.rawValue)! as String
    }

    var bytes: [UInt8]{
        return [UInt8](self)
    }

    var hexString: String {
        var result = ""

        for byte in bytes {
            result += String(format: "%02x", UInt(byte))
        }

        return result.uppercased()
    }
    
}

extension NSData {

    var hexString: String {
        var result = ""

        var bytes = [UInt8](repeating: 0, count: length)
        getBytes(&bytes, length: length)

        for byte in bytes {
            result += String(format: "%02x", UInt(byte))
        }

        return result.uppercased()
    }

}

extension JSON {

    var asArray: NSArray? {
        return object as? NSArray
    }

    var asDictionary: NSDictionary? {
        return object as? NSDictionary
    }

}

extension NSRegularExpression {

    class func match(_ value: String?, pattern: String) -> Bool {
        guard let value = value else {
            return false
        }
        let options = NSRegularExpression.Options()
        let regex = try! NSRegularExpression(pattern: pattern, options: options)
        let range = NSMakeRange(0, value.lengthOfBytes(using: String.Encoding.utf8))
        return regex.rangeOfFirstMatch(in: value, options: [], range: range).location != NSNotFound
    }

    class func extract(_ value: String?, pattern: String) -> String? {
        guard let value = value else {
            return nil
        }
        let options = NSRegularExpression.Options()
        let regex = try! NSRegularExpression(pattern: pattern, options: options)
        let range = NSMakeRange(0, value.lengthOfBytes(using: String.Encoding.utf8))
        let result = regex.firstMatch(in: value, options: [], range: range)
        guard let textRange = result?.range(at: 0) else { return nil }
        let convertedRange =  value.index(value.startIndex, offsetBy: textRange.location)..<value.index(value.startIndex, offsetBy: textRange.location+textRange.length)
        return String(value[convertedRange.lowerBound..<convertedRange.upperBound])
    }

}

extension String {

    func replace(_ value: String, withString string: String) -> String {
        return self.replacingOccurrences(of: value, with: string, options: NSString.CompareOptions.literal, range: nil)
    }

}

extension ARTRealtime {

    func simulateLostConnectionAndState() {
        //1. Abruptly disconnect
        //2. Change the `Connection#id` and `Connection#key` before the client
        //   library attempts to reconnect and resume the connection
        self.connection.internal.setId("lost")
        self.connection.internal.setKey("xxxxx!xxxxxxx-xxxxxxxx-xxxxxxxx")
        self.internal.onDisconnected()
    }

    func simulateSuspended(beforeSuspension beforeSuspensionCallback: @escaping (_ done: @escaping () -> ()) -> Void) {
        waitUntil(timeout: testTimeout) { done in
            self.connection.once(.disconnected) { _ in
                beforeSuspensionCallback(done)
                self.internal.onSuspended()
            }
            self.internal.onDisconnected()
        }
    }

    func simulateNoInternetConnection() {
        guard let reachability = self.internal.reachability as? TestReachability else {
            fatalError("Expected test reachability")
        }

        AblyTests.queue.async {
            TestProxyTransport.fakeNetworkResponse = .noInternet
            reachability.simulate(false)
        }
    }

    func simulateRestoreInternetConnection(after seconds: TimeInterval? = nil) {
        guard let reachability = self.internal.reachability as? TestReachability else {
            fatalError("Expected test reachability")
        }

        AblyTests.queue.asyncAfter(deadline: .now() + (seconds ?? 0)) {
            TestProxyTransport.fakeNetworkResponse = nil
            reachability.simulate(true)
        }
    }

    func overrideConnectionStateTTL(_ ttl: TimeInterval) -> HookToken {
        return self.internal.testSuite_injectIntoMethod(before: NSSelectorFromString("connectionStateTtl")) {
            self.internal.connectionStateTtl = ttl
        }
    }

    func dispose() {
        let names = self.channels.map({ ($0 as! ARTRealtimeChannel).name })
        for name in names {
            self.channels.release(name)
        }
        self.connection.off()
    }

}

extension ARTWebSocketTransport {

    func simulateIncomingNormalClose() {
        let CLOSE_NORMAL = 1000
        self.setState(ARTRealtimeTransportState.closing)
        let webSocketDelegate = self as ARTWebSocketDelegate
        webSocketDelegate.webSocket(self.websocket!, didCloseWithCode: CLOSE_NORMAL, reason: "", wasClean: true)
    }

    func simulateIncomingAbruptlyClose() {
        let CLOSE_ABNORMAL = 1006
        let webSocketDelegate = self as ARTWebSocketDelegate
        webSocketDelegate.webSocket(self.websocket!, didCloseWithCode: CLOSE_ABNORMAL, reason: "connection was closed abnormally", wasClean: false)
    }

    func simulateIncomingError() {
        let error = NSError(domain: ARTAblyErrorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey:"Fail test"])
        let webSocketDelegate = self as ARTWebSocketDelegate
        webSocketDelegate.webSocket(self.websocket!, didFailWithError: error)
    }
}

extension ARTAuthInternal {

    func testSuite_forceTokenToExpire(_ file: StaticString = #file, line: UInt = #line) {
        guard let tokenDetails = self.tokenDetails else {
            XCTFail("TokenDetails is nil", file: file, line: line)
            return
        }
        self.setTokenDetails(ARTTokenDetails(
            token: tokenDetails.token,
            expires: Date().addingTimeInterval(-1.0),
            issued: Date().addingTimeInterval(-1.0),
            capability: tokenDetails.capability,
            clientId: tokenDetails.clientId
            )
        )
    }

}

extension ARTPresenceMessage {

    convenience init(clientId: String, action: ARTPresenceAction, connectionId: String, id: String, timestamp: Date = Date()) {
        self.init()
        self.action = action
        self.clientId = clientId
        self.connectionId = connectionId
        self.id = id
        self.timestamp = timestamp
    }

}

extension ARTMessage {

    convenience init(id: String, name: String? = nil, data: Any) {
        self.init(name: name, data: data)
        self.id = id
    }

}

extension ARTRealtimeConnectionState : CustomStringConvertible {
    public var description : String {
        return ARTRealtimeConnectionStateToStr(self)
    }
}

extension ARTRealtimeConnectionEvent : CustomStringConvertible {
    public var description : String {
        return ARTRealtimeConnectionEventToStr(self)
    }
}

extension ARTProtocolMessageAction : CustomStringConvertible {
    public var description : String {
        return ARTProtocolMessageActionToStr(self)
    }
}

extension ARTRealtimeChannelState : CustomStringConvertible {
    public var description : String {
        return ARTRealtimeChannelStateToStr(self)
    }
}

extension ARTChannelEvent : CustomStringConvertible {
    public var description : String {
        return ARTChannelEventToStr(self)
    }
}

extension ARTPresenceAction : CustomStringConvertible {
    public var description : String {
        return ARTPresenceActionToStr(self)
    }
}

// MARK: - Custom Nimble Matchers

/// A Nimble matcher that succeeds when two dates are quite the same.
public func beCloseTo(_ expectedValue: Date) -> Predicate<Date> {
    let errorMessage = "be close to <\(expectedValue)> (within 0.5)"
    return Predicate.simple(errorMessage) { actualExpression in
        guard let actualValue = try actualExpression.evaluate() else {
            return .fail
        }
        if abs(actualValue.timeIntervalSince1970 - expectedValue.timeIntervalSince1970) < 0.5 {
            return .matches
        }
        return .doesNotMatch
    }
}

/// A Nimble matcher that succeeds when a param exists.
public func haveParam(_ key: String, withValue expectedValue: String? = nil) -> Predicate<String> {
    let errorMessage = "param <\(key)=\(expectedValue ?? "nil")> exists"
    return Predicate.simple(errorMessage) { actualExpression in
        guard let actualValue = try actualExpression.evaluate() else {
            return .fail
        }
        let queryItems = actualValue.components(separatedBy: "&")
        for item in queryItems {
            let param = item.components(separatedBy: "=")
            if let currentKey = param.first, let currentValue = param.last, currentKey == key && currentValue == expectedValue {
                return .matches
            }
        }
        return .doesNotMatch
    }
}


// http://stackoverflow.com/a/26502285/818420
extension String {

    /// Create `NSData` from hexadecimal string representation
    ///
    /// This takes a hexadecimal representation and creates a `NSData` object. Note, if the string has any spaces or non-hex characters (e.g. starts with '<' and with a '>'), those are ignored and only hex characters are processed.
    ///
    /// - returns: Data represented by this hexadecimal string.

    func dataFromHexadecimalString() -> Data? {
        let data = NSMutableData(capacity: self.count / 2)

        let regex = try! NSRegularExpression(pattern: "[0-9a-f]{1,2}", options: .caseInsensitive)
        regex.enumerateMatches(in: self, options: [], range: NSMakeRange(0, self.count)) { match, flags, stop in
            let byteString = (self as NSString).substring(with: match!.range)
            var num = UInt8(byteString, radix: 16)
            data?.append(&num, length: 1)
        }

        return data as Data?
    }
}

@objc class TestReachability : NSObject, ARTReachability {
    var host: String?
    var callback: ((Bool) -> Void)?
    var queue: DispatchQueue

    required init(logger: ARTLog, queue: DispatchQueue) {
        self.queue = queue
    }

    func listen(forHost host: String, callback: @escaping (Bool) -> Void) {
        self.host = host
        self.callback = callback
    }

    func off() {
        self.host = nil
        self.callback = nil
    }

    func simulate(_ reachable: Bool) {
        self.queue.async {
            self.callback!(reachable)
        }
    }
}

extension HTTPURLResponse {

    /**
     This is broken since Swift 3. The access is now case-sensitive.
     Regression: HTTPURLResponse allHeaderFields is now case-sensitive
     https://bugs.swift.org/browse/SR-2429
     - Returns: A dictionary containing all the HTTP header fields of the
     receiver.
     */
    var objc_allHeaderFields: NSDictionary {
        // Disables bridging and calls the Objective-C implementation
        //of the private NSDictionary subclass in CFNetwork directly
        return allHeaderFields as NSDictionary
    }

    /**
     Don't use 'allHeaderFields' property.
     It's not case-insensitive.
     Please use `value(forHTTPHeaderField:)` method.
     - Warning: Don't use 'allHeaderFields' property. See discussion.
     */
    @available(*, deprecated, message: "Don't use 'allHeaderFields'. It's not case-insensitive. Please use 'value(forHTTPHeaderField:)' method")
    open var _allHeaderFields: [AnyHashable : Any] { return [:] }

    /**
     The value which corresponds to the given header
     field. Note that, in keeping with the HTTP RFC, HTTP header field
     names are case-insensitive.
     - Parameter field: the header field name to use for the lookup (case-insensitive).
     */
    func value(forHTTPHeaderField field: String) -> String? {
        return objc_allHeaderFields.object(forKey: field) as? String
    }

}

extension ARTHTTPPaginatedResponse {

    var headers: NSDictionary {
        return response.objc_allHeaderFields
    }
}

protocol ARTHasInternal {
    associatedtype Internal
    func unwrapAsync(_: @escaping (Internal) -> ())
}

extension ARTRealtime: ARTHasInternal {
    typealias Internal = ARTRealtimeInternal
    func unwrapAsync(_ use: @escaping (Internal) -> ()) {
        self.internalAsync(use)
    }
}

extension DispatchTimeInterval {
    /// Convert dispatch time interval to older style time interval for use with XCTest APIs.
    func toTimeInterval() -> TimeInterval {
        // Based on: https://stackoverflow.com/a/47716381/392847
        switch self {
        case .seconds(let value):
            return Double(value)
        case .milliseconds(let value):
            return Double(value) * 0.001
        case .microseconds(let value):
            return Double(value) * 0.000001
        case .nanoseconds(let value):
            return Double(value) * 0.000000001
        case .never:
            return Double.greatestFiniteMagnitude;
        @unknown default:
            fatalError("Unhandled DispatchTimeInterval unit.")
        }
    }

    /// Return a new dispatch time interval computed from this one, multipled by the supplied amount.
    func multiplied(by multiplier: Double) -> DispatchTimeInterval {
        switch self {
        case .seconds(let value):
            return .seconds(Int(Double(value) * multiplier))
        case .milliseconds(let value):
            return .milliseconds(Int(Double(value) * multiplier))
        case .microseconds(let value):
            return .microseconds(Int(Double(value) * multiplier))
        case .nanoseconds(let value):
            return .nanoseconds(Int(Double(value) * multiplier))
        case .never:
            return .never
        @unknown default:
            fatalError("Unhandled DispatchTimeInterval unit.")
        }
    }
    
    /// Return a new dispatch time interval computed from this one, incremented by the supplied amount, to no less than millisecond precision.
    func incremented(by interval: TimeInterval) -> DispatchTimeInterval {
        // interval is a TimeInterval which is a Double which is in SECONDS
        switch self {
        case .seconds(let value):
            // rounding to millisecond precision, which is fine for the purposes of our test needs
            return .milliseconds(Int(1000.0 * (Double(value) + interval)))
        case .milliseconds(let value):
            let millisecondIncrement = interval * 1000.0
            return .milliseconds(Int(Double(value) + millisecondIncrement))
        case .microseconds(let value):
            let microsecondIncrement = interval * 1000000.0
            return .microseconds(Int(Double(value) + microsecondIncrement))
        case .nanoseconds(let value):
            let nanosecondIncrement = interval * 1000000000.0
            return .nanoseconds(Int(Double(value) + nanosecondIncrement))
        case .never:
            return .never
        @unknown default:
            fatalError("Unhandled DispatchTimeInterval unit.")
        }
    }
}
