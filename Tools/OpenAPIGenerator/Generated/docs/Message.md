# Message

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**appid** | **Int64** | The application id that send this message. | [readonly] 
**date** | **Date** | The date the message was created. | [readonly] 
**extras** | **[String: JSONValue]** | The extra data sent along the message.  The extra fields are stored in a key-value scheme. Only accepted in CreateMessage requests with application/json content-type.  The keys should be in the following format: &amp;lt;top-namespace&amp;gt;::[&amp;lt;sub-namespace&amp;gt;::]&amp;lt;action&amp;gt;  These namespaces are reserved and might be used in the official clients: gotify android ios web server client. Do not use them for other purposes. | [optional] 
**id** | **Int64** | The message id. | [readonly] 
**message** | **String** | The message. Markdown (excluding html) is allowed. | 
**priority** | **Int64** | The priority of the message. If unset, then the default priority of the application will be used. | [optional] 
**title** | **String** | The title of the message. | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


