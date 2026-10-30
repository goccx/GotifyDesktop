# MessageAPI

All URIs are relative to *http://localhost*

Method | HTTP request | Description
------------- | ------------- | -------------
[**createMessage**](MessageAPI.md#createmessage) | **POST** /message | Create a message.
[**deleteAppMessages**](MessageAPI.md#deleteappmessages) | **DELETE** /application/{id}/message | Delete all messages from a specific application.
[**deleteMessage**](MessageAPI.md#deletemessage) | **DELETE** /message/{id} | Deletes a message with an id.
[**deleteMessages**](MessageAPI.md#deletemessages) | **DELETE** /message | Delete all messages.
[**getAppMessages**](MessageAPI.md#getappmessages) | **GET** /application/{id}/message | Return all messages from a specific application.
[**getMessages**](MessageAPI.md#getmessages) | **GET** /message | Return all messages.
[**streamMessages**](MessageAPI.md#streammessages) | **GET** /stream | Websocket, return newly created messages.


# **createMessage**
```swift
    open class func createMessage(body: CreateMessage, completion: @escaping (_ data: Message?, _ error: Error?) -> Void)
```

Create a message.

__NOTE__: When authenticating with a client token or basic auth, the request body must include \"appid\" referencing an application owned by the authenticated user. When authenticating with an application token, the application is derived from the token and any \"appid\" in the body is ignored.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient

let body = CreateMessage(appid: 123, extras: "TODO", message: "message_example", priority: 123, title: "title_example") // CreateMessage | the message to add

// Create a message.
MessageAPI.createMessage(body: body) { (response, error) in
    guard error == nil else {
        print(error)
        return
    }

    if (response) {
        dump(response)
    }
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **body** | [**CreateMessage**](CreateMessage.md) | the message to add | 

### Return type

[**Message**](Message.md)

### Authorization

[appTokenAuthorizationHeader](../README.md#appTokenAuthorizationHeader), [appTokenQuery](../README.md#appTokenQuery), [basicAuth](../README.md#basicAuth), [clientTokenQuery](../README.md#clientTokenQuery), [appTokenHeader](../README.md#appTokenHeader), [clientTokenHeader](../README.md#clientTokenHeader), [clientTokenAuthorizationHeader](../README.md#clientTokenAuthorizationHeader)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **deleteAppMessages**
```swift
    open class func deleteAppMessages(id: Int64, completion: @escaping (_ data: Void?, _ error: Error?) -> Void)
```

Delete all messages from a specific application.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient

let id = 987 // Int64 | the application id

// Delete all messages from a specific application.
MessageAPI.deleteAppMessages(id: id) { (response, error) in
    guard error == nil else {
        print(error)
        return
    }

    if (response) {
        dump(response)
    }
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **id** | **Int64** | the application id | 

### Return type

Void (empty response body)

### Authorization

[basicAuth](../README.md#basicAuth), [clientTokenQuery](../README.md#clientTokenQuery), [clientTokenHeader](../README.md#clientTokenHeader), [clientTokenAuthorizationHeader](../README.md#clientTokenAuthorizationHeader)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **deleteMessage**
```swift
    open class func deleteMessage(id: Int64, completion: @escaping (_ data: Void?, _ error: Error?) -> Void)
```

Deletes a message with an id.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient

let id = 987 // Int64 | the message id

// Deletes a message with an id.
MessageAPI.deleteMessage(id: id) { (response, error) in
    guard error == nil else {
        print(error)
        return
    }

    if (response) {
        dump(response)
    }
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **id** | **Int64** | the message id | 

### Return type

Void (empty response body)

### Authorization

[basicAuth](../README.md#basicAuth), [clientTokenQuery](../README.md#clientTokenQuery), [clientTokenHeader](../README.md#clientTokenHeader), [clientTokenAuthorizationHeader](../README.md#clientTokenAuthorizationHeader)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **deleteMessages**
```swift
    open class func deleteMessages(completion: @escaping (_ data: Void?, _ error: Error?) -> Void)
```

Delete all messages.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient


// Delete all messages.
MessageAPI.deleteMessages() { (response, error) in
    guard error == nil else {
        print(error)
        return
    }

    if (response) {
        dump(response)
    }
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

Void (empty response body)

### Authorization

[basicAuth](../README.md#basicAuth), [clientTokenQuery](../README.md#clientTokenQuery), [clientTokenHeader](../README.md#clientTokenHeader), [clientTokenAuthorizationHeader](../README.md#clientTokenAuthorizationHeader)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getAppMessages**
```swift
    open class func getAppMessages(id: Int64, limit: Int? = nil, since: Int64? = nil, completion: @escaping (_ data: PagedMessages?, _ error: Error?) -> Void)
```

Return all messages from a specific application.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient

let id = 987 // Int64 | the application id
let limit = 987 // Int | the maximal amount of messages to return (optional) (default to 100)
let since = 987 // Int64 | return all messages with an ID less than this value (optional)

// Return all messages from a specific application.
MessageAPI.getAppMessages(id: id, limit: limit, since: since) { (response, error) in
    guard error == nil else {
        print(error)
        return
    }

    if (response) {
        dump(response)
    }
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **id** | **Int64** | the application id | 
 **limit** | **Int** | the maximal amount of messages to return | [optional] [default to 100]
 **since** | **Int64** | return all messages with an ID less than this value | [optional] 

### Return type

[**PagedMessages**](PagedMessages.md)

### Authorization

[basicAuth](../README.md#basicAuth), [clientTokenQuery](../README.md#clientTokenQuery), [clientTokenHeader](../README.md#clientTokenHeader), [clientTokenAuthorizationHeader](../README.md#clientTokenAuthorizationHeader)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getMessages**
```swift
    open class func getMessages(limit: Int? = nil, since: Int64? = nil, completion: @escaping (_ data: PagedMessages?, _ error: Error?) -> Void)
```

Return all messages.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient

let limit = 987 // Int | the maximal amount of messages to return (optional) (default to 100)
let since = 987 // Int64 | return all messages with an ID less than this value (optional)

// Return all messages.
MessageAPI.getMessages(limit: limit, since: since) { (response, error) in
    guard error == nil else {
        print(error)
        return
    }

    if (response) {
        dump(response)
    }
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **limit** | **Int** | the maximal amount of messages to return | [optional] [default to 100]
 **since** | **Int64** | return all messages with an ID less than this value | [optional] 

### Return type

[**PagedMessages**](PagedMessages.md)

### Authorization

[basicAuth](../README.md#basicAuth), [clientTokenQuery](../README.md#clientTokenQuery), [clientTokenHeader](../README.md#clientTokenHeader), [clientTokenAuthorizationHeader](../README.md#clientTokenAuthorizationHeader)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **streamMessages**
```swift
    open class func streamMessages(completion: @escaping (_ data: Message?, _ error: Error?) -> Void)
```

Websocket, return newly created messages.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient


// Websocket, return newly created messages.
MessageAPI.streamMessages() { (response, error) in
    guard error == nil else {
        print(error)
        return
    }

    if (response) {
        dump(response)
    }
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**Message**](Message.md)

### Authorization

[basicAuth](../README.md#basicAuth), [clientTokenQuery](../README.md#clientTokenQuery), [clientTokenHeader](../README.md#clientTokenHeader), [clientTokenAuthorizationHeader](../README.md#clientTokenAuthorizationHeader)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

