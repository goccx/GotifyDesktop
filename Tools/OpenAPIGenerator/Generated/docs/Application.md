# Application

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**createdAt** | **Date** | The date the application was created. | [readonly] 
**defaultPriority** | **Int64** | The default priority of messages sent by this application. Defaults to 0. | [optional] 
**description** | **String** | The description of the application. | 
**id** | **Int64** | The application id. | [readonly] 
**image** | **String** | The image of the application. | [readonly] 
**_internal** | **Bool** | Whether the application is an internal application. Internal applications should not be deleted. | [readonly] 
**lastUsed** | **Date** | The last time the application token was used. | [optional] [readonly] 
**name** | **String** | The application name. This is how the application should be displayed to the user. | 
**sortKey** | **String** | The sort key of this application. Uses fractional indexing. | 
**token** | **String** | The application token. Can be used as &#x60;appToken&#x60;. See Authentication. | [optional] [readonly] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


