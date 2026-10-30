# ClientAPI

All URIs are relative to *http://localhost*

Method | HTTP request | Description
------------- | ------------- | -------------
[**createClient**](ClientAPI.md#createclient) | **POST** /client | Create a client.
[**deleteClient**](ClientAPI.md#deleteclient) | **DELETE** /client/{id} | Delete a client.
[**elevateClient**](ClientAPI.md#elevateclient) | **POST** /client/{id}/elevate | Elevate a client session.
[**getClients**](ClientAPI.md#getclients) | **GET** /client | Return all clients.
[**updateClient**](ClientAPI.md#updateclient) | **PUT** /client/{id} | Update a client.


# **createClient**
```swift
    open class func createClient(body: ClientParams, completion: @escaping (_ data: Client?, _ error: Error?) -> Void)
```

Create a client.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient

let body = ClientParams(expiresAfterInactivitySeconds: 123, name: "name_example") // ClientParams | the client to add

// Create a client.
ClientAPI.createClient(body: body) { (response, error) in
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
 **body** | [**ClientParams**](ClientParams.md) | the client to add | 

### Return type

[**Client**](Client.md)

### Authorization

[basicAuth](../README.md#basicAuth), [clientTokenQuery](../README.md#clientTokenQuery), [clientTokenHeader](../README.md#clientTokenHeader), [clientTokenAuthorizationHeader](../README.md#clientTokenAuthorizationHeader)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **deleteClient**
```swift
    open class func deleteClient(id: Int64, completion: @escaping (_ data: Void?, _ error: Error?) -> Void)
```

Delete a client.

Requires elevated authentication.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient

let id = 987 // Int64 | the client id

// Delete a client.
ClientAPI.deleteClient(id: id) { (response, error) in
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
 **id** | **Int64** | the client id | 

### Return type

Void (empty response body)

### Authorization

[basicAuth](../README.md#basicAuth), [clientTokenQuery](../README.md#clientTokenQuery), [clientTokenHeader](../README.md#clientTokenHeader), [clientTokenAuthorizationHeader](../README.md#clientTokenAuthorizationHeader)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **elevateClient**
```swift
    open class func elevateClient(id: Int64, body: ElevateRequest, completion: @escaping (_ data: Void?, _ error: Error?) -> Void)
```

Elevate a client session.

Requires elevated authentication.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient

let id = 987 // Int64 | the client id
let body = ElevateRequest(durationSeconds: 123) // ElevateRequest | the elevation request

// Elevate a client session.
ClientAPI.elevateClient(id: id, body: body) { (response, error) in
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
 **id** | **Int64** | the client id | 
 **body** | [**ElevateRequest**](ElevateRequest.md) | the elevation request | 

### Return type

Void (empty response body)

### Authorization

[basicAuth](../README.md#basicAuth), [clientTokenQuery](../README.md#clientTokenQuery), [clientTokenHeader](../README.md#clientTokenHeader), [clientTokenAuthorizationHeader](../README.md#clientTokenAuthorizationHeader)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getClients**
```swift
    open class func getClients(completion: @escaping (_ data: [Client]?, _ error: Error?) -> Void)
```

Return all clients.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient


// Return all clients.
ClientAPI.getClients() { (response, error) in
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

[**[Client]**](Client.md)

### Authorization

[basicAuth](../README.md#basicAuth), [clientTokenQuery](../README.md#clientTokenQuery), [clientTokenHeader](../README.md#clientTokenHeader), [clientTokenAuthorizationHeader](../README.md#clientTokenAuthorizationHeader)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updateClient**
```swift
    open class func updateClient(id: Int64, body: ClientParams, completion: @escaping (_ data: Client?, _ error: Error?) -> Void)
```

Update a client.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient

let id = 987 // Int64 | the client id
let body = ClientParams(expiresAfterInactivitySeconds: 123, name: "name_example") // ClientParams | the client to update

// Update a client.
ClientAPI.updateClient(id: id, body: body) { (response, error) in
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
 **id** | **Int64** | the client id | 
 **body** | [**ClientParams**](ClientParams.md) | the client to update | 

### Return type

[**Client**](Client.md)

### Authorization

[basicAuth](../README.md#basicAuth), [clientTokenQuery](../README.md#clientTokenQuery), [clientTokenHeader](../README.md#clientTokenHeader), [clientTokenAuthorizationHeader](../README.md#clientTokenAuthorizationHeader)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

