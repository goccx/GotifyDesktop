# OidcAPI

All URIs are relative to *http://localhost*

Method | HTTP request | Description
------------- | ------------- | -------------
[**externalAuthorize**](OidcAPI.md#externalauthorize) | **POST** /auth/oidc/external/authorize | Initiate the OIDC authorization flow for a native app.
[**externalToken**](OidcAPI.md#externaltoken) | **POST** /auth/oidc/external/token | Exchange an authorization code for a gotify client token.
[**oidcCallback**](OidcAPI.md#oidccallback) | **GET** /auth/oidc/callback | Handle the OIDC provider callback (browser).
[**oidcElevate**](OidcAPI.md#oidcelevate) | **GET** /auth/oidc/elevate | Start the OIDC flow to elevate an existing client session (browser).
[**oidcLogin**](OidcAPI.md#oidclogin) | **GET** /auth/oidc/login | Start the OIDC login flow (browser).


# **externalAuthorize**
```swift
    open class func externalAuthorize(body: OIDCExternalAuthorizeRequest, completion: @escaping (_ data: OIDCExternalAuthorizeResponse?, _ error: Error?) -> Void)
```

Initiate the OIDC authorization flow for a native app.

The app generates a PKCE code_verifier and code_challenge, then calls this endpoint. The server forwards the code_challenge to the OIDC provider and returns the authorization URL for the app to open in a browser.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient

let body = OIDCExternalAuthorizeRequest(codeChallenge: "codeChallenge_example", name: "name_example", redirectUri: "redirectUri_example") // OIDCExternalAuthorizeRequest | 

// Initiate the OIDC authorization flow for a native app.
OidcAPI.externalAuthorize(body: body) { (response, error) in
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
 **body** | [**OIDCExternalAuthorizeRequest**](OIDCExternalAuthorizeRequest.md) |  | 

### Return type

[**OIDCExternalAuthorizeResponse**](OIDCExternalAuthorizeResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **externalToken**
```swift
    open class func externalToken(body: OIDCExternalTokenRequest, completion: @escaping (_ data: OIDCExternalTokenResponse?, _ error: Error?) -> Void)
```

Exchange an authorization code for a gotify client token.

After the user authenticates with the OIDC provider and the app receives the authorization code via redirect, the app calls this endpoint with the code and PKCE code_verifier. The server exchanges the code with the OIDC provider and returns a gotify client token.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient

let body = OIDCExternalTokenRequest(code: "code_example", codeVerifier: "codeVerifier_example", state: "state_example") // OIDCExternalTokenRequest | 

// Exchange an authorization code for a gotify client token.
OidcAPI.externalToken(body: body) { (response, error) in
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
 **body** | [**OIDCExternalTokenRequest**](OIDCExternalTokenRequest.md) |  | 

### Return type

[**OIDCExternalTokenResponse**](OIDCExternalTokenResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **oidcCallback**
```swift
    open class func oidcCallback(code: String, state: String, completion: @escaping (_ data: Void?, _ error: Error?) -> Void)
```

Handle the OIDC provider callback (browser).

Exchanges the authorization code for tokens, resolves the user, creates a gotify client, sets a session cookie, and redirects to the UI.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient

let code = "code_example" // String | the authorization code from the OIDC provider
let state = "state_example" // String | the state parameter for CSRF protection

// Handle the OIDC provider callback (browser).
OidcAPI.oidcCallback(code: code, state: state) { (response, error) in
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
 **code** | **String** | the authorization code from the OIDC provider | 
 **state** | **String** | the state parameter for CSRF protection | 

### Return type

Void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **oidcElevate**
```swift
    open class func oidcElevate(id: Int64, durationSeconds: Int, completion: @escaping (_ data: ModelError?, _ error: Error?) -> Void)
```

Start the OIDC flow to elevate an existing client session (browser).

Redirects the user to the OIDC provider's authorization endpoint. After successful authentication, the referenced client session is elevated for the requested duration.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient

let id = 987 // Int64 | the client id to elevate
let durationSeconds = 987 // Int | how long the elevation should last, in seconds

// Start the OIDC flow to elevate an existing client session (browser).
OidcAPI.oidcElevate(id: id, durationSeconds: durationSeconds) { (response, error) in
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
 **id** | **Int64** | the client id to elevate | 
 **durationSeconds** | **Int** | how long the elevation should last, in seconds | 

### Return type

[**ModelError**](ModelError.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **oidcLogin**
```swift
    open class func oidcLogin(name: String, completion: @escaping (_ data: ModelError?, _ error: Error?) -> Void)
```

Start the OIDC login flow (browser).

Redirects the user to the OIDC provider's authorization endpoint. After authentication, the provider redirects back to the callback endpoint.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient

let name = "name_example" // String | the client name to create after login

// Start the OIDC login flow (browser).
OidcAPI.oidcLogin(name: name) { (response, error) in
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
 **name** | **String** | the client name to create after login | 

### Return type

[**ModelError**](ModelError.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

