# PluginAPI

All URIs are relative to *http://localhost*

Method | HTTP request | Description
------------- | ------------- | -------------
[**disablePlugin**](PluginAPI.md#disableplugin) | **POST** /plugin/{id}/disable | Disable a plugin.
[**enablePlugin**](PluginAPI.md#enableplugin) | **POST** /plugin/{id}/enable | Enable a plugin.
[**getPluginConfig**](PluginAPI.md#getpluginconfig) | **GET** /plugin/{id}/config | Get YAML configuration for Configurer plugin.
[**getPluginDisplay**](PluginAPI.md#getplugindisplay) | **GET** /plugin/{id}/display | Get display info for a Displayer plugin.
[**getPlugins**](PluginAPI.md#getplugins) | **GET** /plugin | Return all plugins.
[**updatePluginConfig**](PluginAPI.md#updatepluginconfig) | **POST** /plugin/{id}/config | Update YAML configuration for Configurer plugin.


# **disablePlugin**
```swift
    open class func disablePlugin(id: Int64, completion: @escaping (_ data: Void?, _ error: Error?) -> Void)
```

Disable a plugin.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient

let id = 987 // Int64 | the plugin id

// Disable a plugin.
PluginAPI.disablePlugin(id: id) { (response, error) in
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
 **id** | **Int64** | the plugin id | 

### Return type

Void (empty response body)

### Authorization

[basicAuth](../README.md#basicAuth), [clientTokenQuery](../README.md#clientTokenQuery), [clientTokenHeader](../README.md#clientTokenHeader), [clientTokenAuthorizationHeader](../README.md#clientTokenAuthorizationHeader)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **enablePlugin**
```swift
    open class func enablePlugin(id: Int64, completion: @escaping (_ data: Void?, _ error: Error?) -> Void)
```

Enable a plugin.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient

let id = 987 // Int64 | the plugin id

// Enable a plugin.
PluginAPI.enablePlugin(id: id) { (response, error) in
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
 **id** | **Int64** | the plugin id | 

### Return type

Void (empty response body)

### Authorization

[basicAuth](../README.md#basicAuth), [clientTokenQuery](../README.md#clientTokenQuery), [clientTokenHeader](../README.md#clientTokenHeader), [clientTokenAuthorizationHeader](../README.md#clientTokenAuthorizationHeader)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getPluginConfig**
```swift
    open class func getPluginConfig(id: Int64, completion: @escaping (_ data: JSONValue?, _ error: Error?) -> Void)
```

Get YAML configuration for Configurer plugin.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient

let id = 987 // Int64 | the plugin id

// Get YAML configuration for Configurer plugin.
PluginAPI.getPluginConfig(id: id) { (response, error) in
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
 **id** | **Int64** | the plugin id | 

### Return type

**JSONValue**

### Authorization

[basicAuth](../README.md#basicAuth), [clientTokenQuery](../README.md#clientTokenQuery), [clientTokenHeader](../README.md#clientTokenHeader), [clientTokenAuthorizationHeader](../README.md#clientTokenAuthorizationHeader)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/x-yaml

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getPluginDisplay**
```swift
    open class func getPluginDisplay(id: Int64, completion: @escaping (_ data: String?, _ error: Error?) -> Void)
```

Get display info for a Displayer plugin.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient

let id = 987 // Int64 | the plugin id

// Get display info for a Displayer plugin.
PluginAPI.getPluginDisplay(id: id) { (response, error) in
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
 **id** | **Int64** | the plugin id | 

### Return type

**String**

### Authorization

[basicAuth](../README.md#basicAuth), [clientTokenQuery](../README.md#clientTokenQuery), [clientTokenHeader](../README.md#clientTokenHeader), [clientTokenAuthorizationHeader](../README.md#clientTokenAuthorizationHeader)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getPlugins**
```swift
    open class func getPlugins(completion: @escaping (_ data: [PluginConf]?, _ error: Error?) -> Void)
```

Return all plugins.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient


// Return all plugins.
PluginAPI.getPlugins() { (response, error) in
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

[**[PluginConf]**](PluginConf.md)

### Authorization

[basicAuth](../README.md#basicAuth), [clientTokenQuery](../README.md#clientTokenQuery), [clientTokenHeader](../README.md#clientTokenHeader), [clientTokenAuthorizationHeader](../README.md#clientTokenAuthorizationHeader)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updatePluginConfig**
```swift
    open class func updatePluginConfig(id: Int64, completion: @escaping (_ data: Void?, _ error: Error?) -> Void)
```

Update YAML configuration for Configurer plugin.

### Example
```swift
// The following code samples are still beta. For any issue, please report via http://github.com/OpenAPITools/openapi-generator/issues/new
import GotifyGeneratedClient

let id = 987 // Int64 | the plugin id

// Update YAML configuration for Configurer plugin.
PluginAPI.updatePluginConfig(id: id) { (response, error) in
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
 **id** | **Int64** | the plugin id | 

### Return type

Void (empty response body)

### Authorization

[basicAuth](../README.md#basicAuth), [clientTokenQuery](../README.md#clientTokenQuery), [clientTokenHeader](../README.md#clientTokenHeader), [clientTokenAuthorizationHeader](../README.md#clientTokenAuthorizationHeader)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

