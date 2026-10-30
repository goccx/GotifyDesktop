# AuthAPI

All URIs are relative to *http://localhost*

Method | HTTP request | Description
------------- | ------------- | -------------
[**localLogin**](AuthAPI.md#locallogin) | **POST** /auth/local/login | Authenticate via basic auth and create a session.
[**logout**](AuthAPI.md#logout) | **POST** /auth/logout | End the current session.


# **localLogin**
```swift
    open class func localLogin(name: String, completion: @escaping (_ data: CurrentUser?, _ error: Error?) -> Void)
```

Authenticate via basic auth and create a session.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient

let name = "name_example" // String | the client name to create

// Authenticate via basic auth and create a session.
AuthAPI.localLogin(name: name) { (response, error) in
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
 **name** | **String** | the client name to create | 

### Return type

[**CurrentUser**](CurrentUser.md)

### Authorization

[basicAuth](../README.md#basicAuth)

### HTTP request headers

 - **Content-Type**: application/x-www-form-urlencoded
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **logout**
```swift
    open class func logout(completion: @escaping (_ data: Void?, _ error: Error?) -> Void)
```

End the current session.

Clears the session cookie and deletes the associated client.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient


// End the current session.
AuthAPI.logout() { (response, error) in
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

[basicAuth](../README.md#basicAuth), [clientTokenQuery](../README.md#clientTokenQuery), [clientTokenHeader](../README.md#clientTokenHeader)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

