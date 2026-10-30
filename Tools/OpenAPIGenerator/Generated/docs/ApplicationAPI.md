# ApplicationAPI

All URIs are relative to *http://localhost*

Method | HTTP request | Description
------------- | ------------- | -------------
[**createApp**](ApplicationAPI.md#createapp) | **POST** /application | Create an application.
[**deleteApp**](ApplicationAPI.md#deleteapp) | **DELETE** /application/{id} | Delete an application.
[**getApps**](ApplicationAPI.md#getapps) | **GET** /application | Return all applications.
[**removeAppImage**](ApplicationAPI.md#removeappimage) | **DELETE** /application/{id}/image | Deletes an image of an application.
[**updateAppSecurity**](ApplicationAPI.md#updateappsecurity) | **PUT** /application/{id}/security | Perform security updates on an application.
[**updateApplication**](ApplicationAPI.md#updateapplication) | **PUT** /application/{id} | Update an application.
[**uploadAppImage**](ApplicationAPI.md#uploadappimage) | **POST** /application/{id}/image | Upload an image for an application.


# **createApp**
```swift
    open class func createApp(body: ApplicationParams, completion: @escaping (_ data: Application?, _ error: Error?) -> Void)
```

Create an application.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient

let body = ApplicationParams(defaultPriority: 123, description: "description_example", name: "name_example", sortKey: "sortKey_example") // ApplicationParams | the application to add

// Create an application.
ApplicationAPI.createApp(body: body) { (response, error) in
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
 **body** | [**ApplicationParams**](ApplicationParams.md) | the application to add | 

### Return type

[**Application**](Application.md)

### Authorization

[basicAuth](../README.md#basicAuth), [clientTokenQuery](../README.md#clientTokenQuery), [clientTokenHeader](../README.md#clientTokenHeader), [clientTokenAuthorizationHeader](../README.md#clientTokenAuthorizationHeader)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **deleteApp**
```swift
    open class func deleteApp(id: Int64, completion: @escaping (_ data: Void?, _ error: Error?) -> Void)
```

Delete an application.

Requires elevated authentication.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient

let id = 987 // Int64 | the application id

// Delete an application.
ApplicationAPI.deleteApp(id: id) { (response, error) in
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

# **getApps**
```swift
    open class func getApps(completion: @escaping (_ data: [Application]?, _ error: Error?) -> Void)
```

Return all applications.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient


// Return all applications.
ApplicationAPI.getApps() { (response, error) in
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

[**[Application]**](Application.md)

### Authorization

[basicAuth](../README.md#basicAuth), [clientTokenQuery](../README.md#clientTokenQuery), [clientTokenHeader](../README.md#clientTokenHeader), [clientTokenAuthorizationHeader](../README.md#clientTokenAuthorizationHeader)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **removeAppImage**
```swift
    open class func removeAppImage(id: Int64, completion: @escaping (_ data: Void?, _ error: Error?) -> Void)
```

Deletes an image of an application.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient

let id = 987 // Int64 | the application id

// Deletes an image of an application.
ApplicationAPI.removeAppImage(id: id) { (response, error) in
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

# **updateAppSecurity**
```swift
    open class func updateAppSecurity(id: Int64, body: SecurityUpdateAction, completion: @escaping (_ data: SecurityUpdateActionResponse?, _ error: Error?) -> Void)
```

Perform security updates on an application.

Requires elevated authentication.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient

let id = 987 // Int64 | the application id
let body = SecurityUpdateAction(regenerateToken: true) // SecurityUpdateAction | security update action descriptor

// Perform security updates on an application.
ApplicationAPI.updateAppSecurity(id: id, body: body) { (response, error) in
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
 **body** | [**SecurityUpdateAction**](SecurityUpdateAction.md) | security update action descriptor | 

### Return type

[**SecurityUpdateActionResponse**](SecurityUpdateActionResponse.md)

### Authorization

[basicAuth](../README.md#basicAuth), [clientTokenQuery](../README.md#clientTokenQuery), [clientTokenHeader](../README.md#clientTokenHeader), [clientTokenAuthorizationHeader](../README.md#clientTokenAuthorizationHeader)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updateApplication**
```swift
    open class func updateApplication(id: Int64, body: ApplicationParams, completion: @escaping (_ data: Application?, _ error: Error?) -> Void)
```

Update an application.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient

let id = 987 // Int64 | the application id
let body = ApplicationParams(defaultPriority: 123, description: "description_example", name: "name_example", sortKey: "sortKey_example") // ApplicationParams | the application to update

// Update an application.
ApplicationAPI.updateApplication(id: id, body: body) { (response, error) in
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
 **body** | [**ApplicationParams**](ApplicationParams.md) | the application to update | 

### Return type

[**Application**](Application.md)

### Authorization

[basicAuth](../README.md#basicAuth), [clientTokenQuery](../README.md#clientTokenQuery), [clientTokenHeader](../README.md#clientTokenHeader), [clientTokenAuthorizationHeader](../README.md#clientTokenAuthorizationHeader)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **uploadAppImage**
```swift
    open class func uploadAppImage(id: Int64, file: URL, completion: @escaping (_ data: Application?, _ error: Error?) -> Void)
```

Upload an image for an application.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient

let id = 987 // Int64 | the application id
let file = URL(string: "https://example.com")! // URL | the application image

// Upload an image for an application.
ApplicationAPI.uploadAppImage(id: id, file: file) { (response, error) in
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
 **file** | **URL** | the application image | 

### Return type

[**Application**](Application.md)

### Authorization

[basicAuth](../README.md#basicAuth), [clientTokenQuery](../README.md#clientTokenQuery), [clientTokenHeader](../README.md#clientTokenHeader), [clientTokenAuthorizationHeader](../README.md#clientTokenAuthorizationHeader)

### HTTP request headers

 - **Content-Type**: multipart/form-data
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

