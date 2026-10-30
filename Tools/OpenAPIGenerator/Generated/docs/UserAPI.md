# UserAPI

All URIs are relative to *http://localhost*

Method | HTTP request | Description
------------- | ------------- | -------------
[**createUser**](UserAPI.md#createuser) | **POST** /user | Create a user.
[**currentUser**](UserAPI.md#currentuser) | **GET** /current/user | Return the current user.
[**deleteUser**](UserAPI.md#deleteuser) | **DELETE** /user/{id} | Deletes a user.
[**getUser**](UserAPI.md#getuser) | **GET** /user/{id} | Get a user.
[**getUsers**](UserAPI.md#getusers) | **GET** /user | Return all users.
[**updateCurrentUser**](UserAPI.md#updatecurrentuser) | **POST** /current/user/password | Update the password of the current user.
[**updateUser**](UserAPI.md#updateuser) | **POST** /user/{id} | Update a user.


# **createUser**
```swift
    open class func createUser(body: CreateUserExternal, completion: @escaping (_ data: User?, _ error: Error?) -> Void)
```

Create a user.

With enabled registration: non admin users can be created without authentication. With disabled registrations: users can only be created by admin users.  Requires elevated authentication.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient

let body = CreateUserExternal(admin: true, name: "name_example", pass: "pass_example") // CreateUserExternal | the user to add

// Create a user.
UserAPI.createUser(body: body) { (response, error) in
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
 **body** | [**CreateUserExternal**](CreateUserExternal.md) | the user to add | 

### Return type

[**User**](User.md)

### Authorization

[basicAuth](../README.md#basicAuth), [clientTokenQuery](../README.md#clientTokenQuery), [clientTokenHeader](../README.md#clientTokenHeader), [clientTokenAuthorizationHeader](../README.md#clientTokenAuthorizationHeader)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **currentUser**
```swift
    open class func currentUser(completion: @escaping (_ data: User?, _ error: Error?) -> Void)
```

Return the current user.

Requires elevated authentication.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient


// Return the current user.
UserAPI.currentUser() { (response, error) in
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

[**User**](User.md)

### Authorization

[basicAuth](../README.md#basicAuth), [clientTokenQuery](../README.md#clientTokenQuery), [clientTokenHeader](../README.md#clientTokenHeader), [clientTokenAuthorizationHeader](../README.md#clientTokenAuthorizationHeader)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **deleteUser**
```swift
    open class func deleteUser(id: Int64, completion: @escaping (_ data: Void?, _ error: Error?) -> Void)
```

Deletes a user.

Requires elevated authentication.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient

let id = 987 // Int64 | the user id

// Deletes a user.
UserAPI.deleteUser(id: id) { (response, error) in
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
 **id** | **Int64** | the user id | 

### Return type

Void (empty response body)

### Authorization

[basicAuth](../README.md#basicAuth), [clientTokenQuery](../README.md#clientTokenQuery), [clientTokenHeader](../README.md#clientTokenHeader), [clientTokenAuthorizationHeader](../README.md#clientTokenAuthorizationHeader)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getUser**
```swift
    open class func getUser(id: Int64, completion: @escaping (_ data: User?, _ error: Error?) -> Void)
```

Get a user.

Requires elevated authentication.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient

let id = 987 // Int64 | the user id

// Get a user.
UserAPI.getUser(id: id) { (response, error) in
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
 **id** | **Int64** | the user id | 

### Return type

[**User**](User.md)

### Authorization

[basicAuth](../README.md#basicAuth), [clientTokenQuery](../README.md#clientTokenQuery), [clientTokenHeader](../README.md#clientTokenHeader), [clientTokenAuthorizationHeader](../README.md#clientTokenAuthorizationHeader)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getUsers**
```swift
    open class func getUsers(completion: @escaping (_ data: [User]?, _ error: Error?) -> Void)
```

Return all users.

Requires elevated authentication.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient


// Return all users.
UserAPI.getUsers() { (response, error) in
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

[**[User]**](User.md)

### Authorization

[basicAuth](../README.md#basicAuth), [clientTokenQuery](../README.md#clientTokenQuery), [clientTokenHeader](../README.md#clientTokenHeader), [clientTokenAuthorizationHeader](../README.md#clientTokenAuthorizationHeader)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updateCurrentUser**
```swift
    open class func updateCurrentUser(body: UserPass, completion: @escaping (_ data: Void?, _ error: Error?) -> Void)
```

Update the password of the current user.

Requires elevated authentication.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient

let body = UserPass(pass: "pass_example") // UserPass | the user

// Update the password of the current user.
UserAPI.updateCurrentUser(body: body) { (response, error) in
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
 **body** | [**UserPass**](UserPass.md) | the user | 

### Return type

Void (empty response body)

### Authorization

[basicAuth](../README.md#basicAuth), [clientTokenQuery](../README.md#clientTokenQuery), [clientTokenHeader](../README.md#clientTokenHeader), [clientTokenAuthorizationHeader](../README.md#clientTokenAuthorizationHeader)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updateUser**
```swift
    open class func updateUser(id: Int64, body: UpdateUserExternal, completion: @escaping (_ data: User?, _ error: Error?) -> Void)
```

Update a user.

Requires elevated authentication.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient

let id = 987 // Int64 | the user id
let body = UpdateUserExternal(admin: true, name: "name_example", pass: "pass_example") // UpdateUserExternal | the updated user

// Update a user.
UserAPI.updateUser(id: id, body: body) { (response, error) in
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
 **id** | **Int64** | the user id | 
 **body** | [**UpdateUserExternal**](UpdateUserExternal.md) | the updated user | 

### Return type

[**User**](User.md)

### Authorization

[basicAuth](../README.md#basicAuth), [clientTokenQuery](../README.md#clientTokenQuery), [clientTokenHeader](../README.md#clientTokenHeader), [clientTokenAuthorizationHeader](../README.md#clientTokenAuthorizationHeader)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

