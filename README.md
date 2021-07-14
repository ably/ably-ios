# [Ably](https://www.ably.io) iOS, tvOS and macOS Objective-C and Swift client library SDK

[![.github/workflows/check.yml](https://github.com/ably/ably-cocoa/actions/workflows/check.yml/badge.svg)](https://github.com/ably/ably-cocoa/actions/workflows/check.yml)
[![CocoaPods Compatible](https://img.shields.io/cocoapods/v/Ably.svg)](https://img.shields.io/cocoapods/v/Ably.svg)
[![Carthage Compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)

iOS, tvOS and macOS Objective-C and Swift client library SDK for [Ably realtime messaging service](https://www.ably.io), written in Objective-C. This library currently targets the [Ably client library features spec](https://www.ably.io/documentation/client-lib-development-guide/features/) Version 1.2. You can jump to the '[Known Limitations](#known-limitations)' section to see the features this client library does not yet support or [view our client library SDKs feature support matrix](https://www.ably.io/download/sdk-feature-support-matrix) to see the list of all the available features.

- [Supported platforms](#supported-platforms)
	- [Acknowledgments](#acknowledgments)
- [Known Limitations](#known-limitations)
- [Documentation](#documentation)
- [Installation Guide](#installation-guide)
	- [CocoaPods](#installing-through-cocoapods)
	- [Carthage](#installing-through-carthage)
	- [Manual](#manual-installation)
- [Thread-safety Acknowledgments](#thread-safety)
- [Push Notifications](#push-notifications)
- [Using the Realtime API](#using-the-realtime-api)
	- [Connection](#connection)
	- [Subscribing to a channel](#subscribing-to-a-channel)
	- [Publishing to a channel](#publishing-to-a-channel)
	- [Querying the history](#querying-the-history)
	- [Presence on a channel](#presence-on-a-channel)
	- [Querying the presence history](#querying-the-presence-history)
	- [Using the authCallback](#using-the-authCallback)
- [Using the REST API](#using-the-rest-api)
	- [Publishing a message to a channel](#publishing-a-message-to-a-channel)
	- [Querying the history](#querying-the-history)
	- [Presence on a channel](#presence-on-a-channel)
	- [Querying the presence history](#querying-the-presence-history)
	- [Generate token](#generate-token)
	- [Fetching your application's stats](#fetching-your-applications-stats)
	- [Fetching the Ably service time](#fetching-the-ably-service-time)
- [Support, feedback and troubleshooting](#support-feedback-and-troubleshooting)
- [Contributing](#contributing)
    - [Development Flow](#development-flow)
- [Running tests](#running-tests)
- [Release Process](#release-process)

## Supported platforms

This SDK is compatible with projects that target:

- iOS 9.0+
- tvOS 10.0+
- macOS 10.11+

We maintain compatibility and explicitly support these platform versions, including performing CI testing on all library revisions.

We do not explicitly maintain compatibility with older platform versions; we no longer perform CI testing on iOS 8 as of version 1.0.12 (released on January 31st 2018). Any known incompatibilities with older versions can be found [here](https://github.com/ably/ably-cocoa/issues?q=is%3Aissue+is%3Aopen+label%3A%22compatibility%22).

If you find any issues with unsupported platform versions, please [raise an issue](https://github.com/ably/ably-cocoa/issues) in this repository or [contact Ably customer support](https://support.ably.io) for advice.

## Known Limitations

This client library is currently *not compatible* with some of the Ably features:

| Feature |
| :--- |
| [Custom transportParams](https://ably.io/documentation/realtime/usage#client-options) |
| [Remember fallback host during failures](https://ably.io/documentation/realtime/usage#client-options) | 
| [ErrorInfo URLs to help debug issues](https://ably.io/documentation/realtime/types#error-info) |

## Documentation

Visit [ably.io/documentation](https://www.ably.io/documentation) for a complete API reference and more examples.

## Installation Guide

You can install Ably for iOS and macOS through Package Manager, CocoaPods, Carthage or manually.

## Installation

### Installing through [Swift Package Manager](https://swift.org/package-manager/)
- To install the `ably-cocoa` package in your **Xcode Project**: 
    - Paste `https://github.com/ably/ably-cocoa` in the *Swift Packages* search box. ( *Xcode project*  &rarr;  *Swift Packages..* . &rarr; `+` button)
    - Select the `Ably` SDK for your target.
    - [This apple guide](https://developer.apple.com/documentation/swift_packages/adding_package_dependencies_to_your_app) explains the steps in more detail.
- To install the `ably-cocoa` package in another **Swift Package**, then add the following to your `Package.Swift`:
```swift
 .package(url: "https://github.com/ably/ably-cocoa", from: "1.3.0"),
```
### Installing through [CocoaPods](https://cocoapods.org/)

If you intend to use Swift, using `use_frameworks!` in your Podfile is recommended (this will create a Framework that can be used in Swift natively).

Add this line to your application's Podfile:

    # For Xcode 7.3 and newer
    pod 'Ably', '>= 1.2'

And then install the dependency:

    $ pod install

### Installing through [Carthage](https://github.com/Carthage/Carthage/)

Add this line to your application's Cartfile:

    # For Xcode 7.3 and newer
    github "ably/ably-cocoa" >= 1.2

And then run  

- for **iOS**: `carthage update --use-xcframeworks --platform iOS --no-use-binaries`
- for **macOS**: `carthage update --use-xcframeworks --platform macOS --no-use-binaries`
- for **tvOS**: `carthage update --use-xcframeworks --platform tvOS --no-use-binaries`

to build the framework and drag the built (in `[PROJECT_ROOT]/Carthage/Build`)

- `Ably.xcframework` 
- `AblyDeltaCodec.xcframework`
- `msgpack.xcframework`

into your Xcode project.

If you see, for example, a `dyld: Library not loaded: @rpath/AblyDeltaCodec.framework/AblyDeltaCodec` error, then most likely you forgot to add all the dependencies to your project. You have more detailed information [here](https://github.com/Carthage/Carthage#adding-frameworks-to-an-application).

### Manual installation 

1. Get the code from GitHub [from the release page](https://github.com/ably/ably-cocoa/releases/tag/1.2.4), or clone it to get the latest, unstable and possibly underdocumented version: `git clone git@github.com:ably/ably-cocoa.git`
2. Drag the directory `ably-cocoa/ably-cocoa` into your project as a group.
3. Ably depends on our [MessagePack Fork](https://github.com/ably-forks/msgpack-objective-C) 0.2.0; get it [from the releases page](https://github.com/ably-forks/msgpack-objective-C/releases/tag/0.2.0-ably-1) and link it into your project.

## Thread-safety

The library makes the following thread-safety guarantees:

* The whole public interface can be safely accessed, both for read and writing, from any thread.
* "Value" objects (e. g. `ARTTokenDetails`, data from messages) returned by the library can be safely read from and written to.
* Objects passed to the library must not be mutated afterwards. They can be safely passed again, or read from; they won't be written to by the library.

All internal operations are dispatched to a single serial GCD queue. You can specify a custom queue for this, which must be serial, with `ARTClientOptions.internalDispatchQueue`.

All calls to callbacks provided by the user are dispatched to the main queue by default.
This allows you to react to Ably's output by doing UI operations directly. You can specify a different queue with `ARTClientOptions.dispatchQueue`. It shouldn't be the same queue as the `ARTClientOptions.internalDispatchQueue`, since that can lead to deadlocks.

## Push Notifications

If you haven’t yet, you should first check the detailed [documentation](https://www.ably.io/documentation/general/push).

### Activation and device registration

**`ARTPushRegistererDelegate`** is the interface for handling Push activation/deactivation-related actions. The activation process, by default, will check if the `UIApplication.sharedApplication.delegate` has the `ARTPushRegistererDelegate` implementation.

Since version 1.2.4, there's a new way to pass the `ARTPushRegistererDelegate` implementation into the library. It must be used for new apps created with Xcode 12 and later, using the SwiftUI App Lifecycle. You can assign the delegate directly in the client options using the `pushRegistererDelegate` property, without relying on `UIApplicationDelegate`.

Do not forget that `ARTPush` has two corresponding methods that you should call from yours [application(_:didRegisterForRemoteNotificationsWithDeviceToken:)](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1622958-application) and [application(_:didFailToRegisterForRemoteNotificationsWithError:)](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1622962-application), passing to them also an `ARTRest` or `ARTRealtime` instance, configured with the authentication setup and other options you need:

```
func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    ARTPush.didRegisterForRemoteNotifications(withDeviceToken: deviceToken, rest: rest)
}

func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    ARTPush.didFailToRegisterForRemoteNotificationsWithError(error, rest: rest)
}
```

Only one instance of `ARTRest` or `ARTRealtime` at a time must be [activated for receiving push notifications](https://www.ably.io/documentation/general/push/activate-subscribe). Having more than one activated instance at a time may have unexpected consequences.

### macOS & tvOS

Be aware that Push Notifications are currently unsupported for macOS and tvOS. You can only use the [Push Admin](https://www.ably.io/documentation/general/push/admin) functionalities, for example:

```swift
let recipient: [String: Any] = [
    "clientId": "C04BC116-8004-4D78-A71F-8CA3122734DB"
]
let data: [String: Any] = [
    "notification": [
        "title": "Hello from Ably!",
        "body": "Example push notification from Ably."
    ],
    "data": [
        "foo": "bar",
        "baz": "qux"
    ]
]
realtime.push.admin.publish(recipient, data: data) { error in
    print("Push published:", error ?? "nil")
}
```

Available demos: [macOS](https://github.com/ably/demo-macos) and [tvOS](https://github.com/ably/demo-tvos).

## Using the Realtime API

<!--
NOTE NOTE NOTE NOTE NOTE NOTE NOTE NOTE NOTE N
**********************************************
==============================================

(Sorry for the noise.)

Those examples need to be kept in sync with:

Spec/ReadmeExamples.swift

==============================================
**********************************************
OTE NOTE NOTE NOTE NOTE NOTE NOTE NOTE NOTE NO
-->

### Introduction

All examples assume a client has been created as follows:

**Swift**

```swift
// basic auth with an API key
let client = ARTRealtime(key: "xxxx:xxxx")

// using token auth
let client = ARTRealtime(token: "xxxx")
```

**Objective-C**

```objective-c
// basic auth with an API key
ARTRealtime* client = [[ARTRealtime alloc] initWithKey:@"xxxx:xxxx"];

// using token auth
ARTRealtime* client = [[ARTRealtime alloc] initWithToken:@"xxxx"];
```

### Connection

Instantiating `ARTRealtime` starts a connection by default. You can catch connection success or error by listening to the connection's state changes:

**Swift**

```swift
client.connection.on { stateChange in
    let stateChange = stateChange!
    switch stateChange.current {
    case .Connected:
        print("connected!")
    case .Failed:
        print("failed! \(stateChange.reason)")
    default:
        break
    }
}
```

**Objective-C**

```objective-c
[client.connection on:^(ARTConnectionStateChange *stateChange) {
    switch (stateChange.current) {
        case ARTRealtimeConnected:
            NSLog(@"connected!");
            break;
        case ARTRealtimeFailed:
            NSLog(@"failed! %@", stateChange.reason);
            break;
        default:
            break;
    }
}];
```

You can also connect manually by setting the appropriate option.

**Swift**

```swift
let options = ARTClientOptions(key: "xxxx:xxxx")
options.autoConnect = false
let client = ARTRealtime(options: options)
client.connection.connect()
```

**Objective-C**

```objective-c
ARTClientOptions *options = [[ARTClientOptions alloc] initWithKey:@"xxxx:xxxx"];
options.autoConnect = false;
ARTRealtime *client = [[ARTRealtime alloc] initWithOptions:options];
[client.connection connect];
```

### Subscribing to a channel

Given:

**Swift**

```swift
let channel = client.channels.get("test")
```

**Objective-C**

```objective-c
ARTRealtimeChannel *channel = [client.channels get:@"test"];
```

Subscribe to all events:

**Swift**

```swift
channel.subscribe { message in
    print(message.name)
    print(message.data)
}
```

**Objective-C**

```objective-c
[channel subscribe:^(ARTMessage *message) {
    NSLog(@"%@", message.name);
    NSLog(@"%@", message.data);
}];
```

Only certain events:

**Swift**

```swift
channel.subscribe("myEvent") { message in
    print(message.name)
    print(message.data)
}
```

**Objective-C**

```objective-c
[channel subscribe:@"myEvent" callback:^(ARTMessage *message) {
    NSLog(@"%@", message.name);
    NSLog(@"%@", message.data);
}];
```

### Subscribing to a channel in delta mode

Subscribing to a channel in delta mode enables [delta compression](https://www.ably.io/documentation/realtime/channels/channel-parameters/deltas). This is a way for a client to subscribe to a channel so that message payloads sent contain only the difference (ie the delta) between the present message and the previous message on the channel.

Request a Vcdiff formatted delta stream using channel options when you get the channel:
 
**Swift**

```swift
let channelOptions = ARTRealtimeChannelOptions()
channelOptions.params = [
    "delta": "vcdiff"
]

let channel = client.channels.get("test", options: channelOptions)
```

**Objective-C**

```objective-c
ARTRealtimeChannelOptions *channelOptions = [[ARTRealtimeChannelOptions alloc] init];
channelOptions.params = @{
    @"delta": @"vcdiff"
};

ARTRealtimeChannel *channel = [client.channels get:@"test" options:channelOptions];
```

Beyond specifying channel options, the rest is transparent and requires no further changes to your application. The `message.data` instances that are delivered to your subscription callback continue to contain the values that were originally published.

If you would like to inspect the `ARTMessage` instances in order to identify whether the `data` they present was rendered from a delta message from Ably then you can see if `message.extras["delta"]["format"]` equals `"vcdiff"`.

### Publishing to a channel

**Swift**

```swift
channel.publish("greeting", data: "Hello World!")
```

**Objective-C**

```objective-c
[channel publish:@"greeting" data:@"Hello World!"];
```

### Querying the history

**Swift**

```swift
channel.history { messagesPage, error in
    let messagesPage = messagesPage!
    print(messagesPage.items)
    print(messagesPage.items.first)
    print((messagesPage.items.first as? ARTMessage)?.data) // payload for the message
    print(messagesPage.items.count) // number of messages in the current page of history
    messagesPage.next { nextPage, error in
        // retrieved the next page in nextPage
    }
    print(messagesPage.hasNext) // true, there are more pages
}
```

**Objective-C**

```objective-c
[channel history:^(ARTPaginatedResult<ARTMessage *> *messagesPage, ARTErrorInfo *error) {
    NSLog(@"%@", messagesPage.items);
    NSLog(@"%@", messagesPage.items.firstObject);
    NSLog(@"%@", messagesPage.items.firstObject.data); // payload for the message
    NSLog(@"%lu", (unsigned long)[messagesPage.items count]); // number of messages in the current page of history
    [messagesPage next:^(ARTPaginatedResult<ARTMessage *> *nextPage, ARTErrorInfo *error) {
        // retrieved the next page in nextPage
    }];
    NSLog(@"%d", messagesPage.hasNext); // true, there are more pages
}];
```

### Presence on a channel

**Swift**

```swift
let channel = client.channels.get("test")

channel.presence.enter("john.doe") { errorInfo in
    channel.presence.get { members, errorInfo in
        // members is the array of members present
    }
}
```

**Objective-C**

```objective-c
[channel.presence enter:@"john.doe" callback:^(ARTErrorInfo *errorInfo) {
    [channel.presence get:^(ARTPaginatedResult<ARTPresenceMessage *> *result, ARTErrorInfo *error) {
        // members is the array of members present
    }];
}];
```

### Querying the presence history

**Swift**

```swift
channel.presence.history { presencePage, error in
    let presencePage = presencePage!
    if let first = presencePage.items.first as? ARTPresenceMessage {
        print(first.action) // Any of .Enter, .Update or .Leave
        print(first.clientId) // client ID of member
        print(first.data) // optional data payload of member
        presencePage.next { nextPage, error in
            // retrieved the next page in nextPage
        }
    }
}
```

**Objective-C**

```objective-c
[channel.presence history:^(ARTPaginatedResult<ARTPresenceMessage *> *presencePage, ARTErrorInfo *error) {
    ARTPresenceMessage *first = (ARTPresenceMessage *)presencePage.items.firstObject;
    NSLog(@"%lu", (unsigned long)first.action); // Any of ARTPresenceEnter, ARTPresenceUpdate or ARTPresenceLeave
    NSLog(@"%@", first.clientId); // client ID of member
    NSLog(@"%@", first.data); // optional data payload of member
    [presencePage next:^(ARTPaginatedResult<ARTPresenceMessage *> *nextPage, ARTErrorInfo *error) {
        // retrieved the next page in nextPage
    }];
}];
```

### Using the `authCallback`

A callback to call to obtain a signed token request.  
`ARTClientOptions` and `ARTRealtime` objects can be instantiated as follow:

**Swift**

```swift
let clientOptions = ARTClientOptions()
clientOptions.authCallback = { params, callback in
    getTokenRequestJSONFromYourServer(params) { json, error in
        //handle error
        do {
            callback(try ARTTokenRequest.fromJson(json), nil)
        } catch let error as NSError {
            callback(nil, error)
        }
    }
}

let client = ARTRealtime(options:clientOptions)
```

**Objective-C**

```objective-c
ARTClientOptions *clientOptions = [[ARTClientOptions alloc] init];
clientOptions.authCallback = ^(ARTTokenParams *params, void(^callback)(id<ARTTokenDetailsCompatible>, NSError*)) {
    [self getTokenRequestJSONFromYourServer:params completion:^(NSDictionary *json, NSError *error) {
        //handle error
        ARTTokenRequest *tokenRequest = [ARTTokenRequest fromJson:json error:&error];
        callback(tokenRequest, error);
    }];
};

ARTRealtime *client = [[ARTRealtime alloc] initWithOptions:clientOptions];
```

## Using the REST API

### Introduction

All examples assume a client and/or channel has been created as follows:

**Swift**

```swift
let client = ARTRest(key: "xxxx:xxxx")
let channel = client.channels.get("test")
```

**Objective-C**

```objective-c
ARTRest *client = [[ARTRest alloc] initWithKey:@"xxxx:xxxx"];
ARTRestChannel *channel = [client.channels get:@"test"];
```

### Publishing a message to a channel

**Swift**

```swift
channel.publish("myEvent", data: "Hello!")
```

**Objective-C**

```objective-c
[channel publish:@"myEvent" data:@"Hello!"];
```

### Querying the history

**Swift**

```swift
channel.history { messagesPage, error in
    let messagesPage = messagesPage!
    print(messagesPage.items.first)
    print((messagesPage.items.first as? ARTMessage)?.data) // payload for the message
    messagesPage.next { nextPage, error in
        // retrieved the next page in nextPage
    }
    print(messagesPage.hasNext) // true, there are more pages
}
```

**Objective-C**

```objective-c
[channel history:^(ARTPaginatedResult<ARTMessage *> *messagesPage, ARTErrorInfo *error) {
    NSLog(@"%@", messagesPage.items.firstObject);
    NSLog(@"%@", messagesPage.items.firstObject.data); // payload for the message
    NSLog(@"%lu", (unsigned long)[messagesPage.items count]); // number of messages in the current page of history
    [messagesPage next:^(ARTPaginatedResult<ARTMessage *> *nextPage, ARTErrorInfo *error) {
        // retrieved the next page in nextPage
    }];
    NSLog(@"%d", messagesPage.hasNext); // true, there are more pages
}];
```

### Presence on a channel

**Swift**

```swift
channel.presence.get { membersPage, error in
    let membersPage = membersPage!
    print(membersPage.items.first)
    print((membersPage.items.first as? ARTPresenceMessage)?.data) // payload for the message
    membersPage.next { nextPage, error in
        // retrieved the next page in nextPage
    }
    print(membersPage.hasNext) // true, there are more pages
}
```

**Objective-C**

```objective-c
[channel.presence get:^(ARTPaginatedResult<ARTPresenceMessage *> *membersPage, ARTErrorInfo *error) {
    NSLog(@"%@", membersPage.items.firstObject);
    NSLog(@"%@", membersPage.items.firstObject.data); // payload for the message
    [membersPage next:^(ARTPaginatedResult<ARTMessage *> *nextPage, ARTErrorInfo *error) {
        // retrieved the next page in nextPage
    }];
    NSLog(@"%d", membersPage.hasNext); // true, there are more pages
}];
```

### Querying the presence history

**Swift**

```swift
channel.presence.history { presencePage, error in
    let presencePage = presencePage!
    if let first = presencePage.items.first as? ARTPresenceMessage {
        print(first.clientId) // client ID of member
        presencePage.next { nextPage, error in
            // retrieved the next page in nextPage
        }
    }
}
```

**Objective-C**

```objective-c
[channel.presence history:^(ARTPaginatedResult<ARTPresenceMessage *> *presencePage, ARTErrorInfo *error) {
    ARTPresenceMessage *first = (ARTPresenceMessage *)presencePage.items.firstObject;
    NSLog(@"%@", first.clientId); // client ID of member
    NSLog(@"%@", first.data); // optional data payload of member
    [presencePage next:^(ARTPaginatedResult<ARTPresenceMessage *> *nextPage, ARTErrorInfo *error) {
        // retrieved the next page in nextPage
    }];
}];
```

### Generate token

**Swift**

```swift
client.auth.requestToken(nil, withOptions: nil) { tokenDetails, error in
    let tokenDetails = tokenDetails!
    print(tokenDetails.token) // "xVLyHw.CLchevH3hF....MDh9ZC_Q"
    let client = ARTRest(token: tokenDetails.token)
}
```

**Objective-C**

```objective-c
[client.auth requestToken:nil withOptions:nil callback:^(ARTTokenDetails *tokenDetails, NSError *error) {
    NSLog(@"%@", tokenDetails.token); // "xVLyHw.CLchevH3hF....MDh9ZC_Q"
    ARTRest *client = [[ARTRest alloc] initWithToken:tokenDetails.token];
}];
```

### Fetching your application's stats

**Swift**

```swift
client.stats { statsPage, error in
    let statsPage = statsPage!
    print(statsPage.items.first)
    statsPage.next { nextPage, error in
        // retrieved the next page in nextPage
    }
}
```

**Objective-C**

```objective-c
[client stats:^(ARTPaginatedResult<ARTStats *> *statsPage, ARTErrorInfo *error) {
    NSLog(@"%@", statsPage.items.firstObject);
    [statsPage next:^(ARTPaginatedResult<ARTStats *> *nextPage, ARTErrorInfo *error) {
        // retrieved the next page in nextPage
    }];
}];
```

### Fetching the Ably service time

**Swift**

```swift
client.time { time, error in
    print(time) // 2016-02-09 03:59:24 +0000
}
```

**Objective-C**

```objective-c
[client time:^(NSDate *time, NSError *error) {
    NSLog(@"%@", time); // 2016-02-09 03:59:24 +0000
}];
```

## Support, feedback and troubleshooting

Please visit https://support.ably.io/ for access to our knowledgebase and to ask for any assistance.

You can also view the [community reported Github issues](https://github.com/ably/ably-cocoa/issues).

## Contributing

In this repository the `main` branch contains the latest development version of the Ably SDK. All development (bug fixing, feature implementation, etc.) is done against the `main` branch, which you should branch from whenever you'd like to make modifications. Here's the steps to follow when contributing to this repository.

1. Fork it
2. Setup or update your machine by running `make setup|update`
3. Create your feature branch from `main` (`git checkout main && git checkout -b my-new-feature-branch`)
4. Commit your changes (`git commit -am 'Add some feature'`)
5. Ensure you have added suitable tests and the test suite is passing
6. Push to the branch (`git push origin my-new-feature-branch`)
7. Create a new Pull Request

Releases of the Ably SDK built by the sources in this repository are tagged with their [semantic version](http://semver.org/) numbers.

### Development Flow

When you first clone the repository then you will need to run `make update` in order to
bring in Git submodules and Carthage dependencies.

Code can then be modified, built and tested by loading [Ably.xcodeproj](Ably.xcodeproj) in your Xcode IDE.

The Xcode project relies upon dependencies resolved by Carthage.
If you make changes to the [Cartfile](Cartfile) then you will need to run `make update_carthage_dependencies`
from the command line and then do a clean rebuild in Xcode.

Changes made to dependencies in the [Cartfile](Cartfile) need to be reflected in
[Ably.podspec](Ably.podspec) and vice-versa.

## Running tests

To run tests use `make test_[iOS|tvOS|macOS]`.

Note: [Fastlane](https://fastlane.tools) should be installed.

## Release Process

For each release, the following needs to be done:

* Create a new branch `release/x.x.x` (where `x.x.x` is the new version number) from the `main` branch
* Run `make bump_[major|minor|patch]` to bump the new version number (creates a Git commit)
* Run [`github_changelog_generator`](https://github.com/github-changelog-generator/github-changelog-generator) to automate the update of the [CHANGELOG](./CHANGELOG.md). This may require some manual intervention, both in terms of how the command is run and how the change log file is modified. Your mileage may vary:
    * The command you will need to run will look something like this: `github_changelog_generator -u ably -p ably-cocoa --since-tag 1.2.4 --output delta.md`
    * Using the command above, `--output delta.md` writes changes made after `--since-tag` to a new file
    * The contents of that new file (`delta.md`) then need to be manually inserted at the top of the `CHANGELOG.md`, changing the "Unreleased" heading and linking with the current version numbers
    * Also ensure that the "Full Changelog" link points to the new version tag instead of the `HEAD`
    * Commit this change: `git add CHANGELOG.md && git commit -m "Update change log."`
* Push both commits to origin: `git push -u origin release/x.x.x`
* Make a pull request against `main` and await approval of reviewer(s)
* Once approved and/or any additional commits have been added, merge the PR (f you do this from Github's web interface then use the "Rebase and merge" option)
* Steps to perform *before* pushing a release tag up:
    1. Checkout `main` locally, pulling in changes from above using `git checkout main && git pull`
    2. Run `make update` to ensure Carthage dependencies are in sync
    3. Generate the prebuilt framework for Carthage using `make carthage_package platform=[iOS|macOS|tvOS]` (the output from this, `Ably.framework.zip`, will be attached to the release later on)
    4. Validate that the CocoaPods build should succeed using `pod lib lint`
* If any fixes are needed (e.g. the lint fails with warnings) then either commit them to `main` branch now if they are simple warning fixes or perhaps consider raising a new PR if they are complex or likely to need review.
* Create a tag for this version number using `git tag x.x.x`
* Push the tag using `git push origin x.x.x`
* Release an update for CocoaPods using `pod trunk push Ably.podspec`. Details on this command, as well as instructions for adding other contributors as maintainers, are at [Getting setup with Trunk](https://guides.cocoapods.org/making/getting-setup-with-trunk.html) in the [CocoaPods Guides](https://guides.cocoapods.org/)
* Add to [releases](https://github.com/ably/ably-cocoa/releases)
    * refer to previous releases for release notes format
    * attach the prebuilt framework file generated by Carthage to the release: `Ably.framework.zip`
* Test the integration of the library in a Xcode project using Carthage and CocoaPods using the [installation guide](https://github.com/ably/ably-cocoa#installation-guide)
